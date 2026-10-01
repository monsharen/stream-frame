import { EventEmitter } from 'node:events';
import type { Page } from 'playwright-core';
import type { ChromeHost } from './chrome.ts';
import type { ServiceAdapter } from './services/types.ts';

export type PlaybackStatus = 'idle' | 'loading' | 'playing' | 'paused' | 'ended' | 'error';

export type PlaybackState = {
  status: PlaybackStatus;
  service?: string;
  title?: string;
  watchUrl?: string;
  position: number;
  duration: number;
  error?: string;
};

type VideoSnapshot = { currentTime: number; duration: number; paused: boolean; ended: boolean };

const POLL_MS = 500;
const START_TIMEOUT_MS = 60_000;
// How long the video may be missing (site navigated away, error page, browser
// gone) before the session is considered over. Covers brief gaps such as a
// player swapping its <video> element between episodes.
const LOST_VIDEO_POLLS = 10;

function readVideo(page: Page): Promise<VideoSnapshot | null> {
  return page.evaluate(() => {
    const v = document.querySelector('video');
    if (!v) return null;
    return { currentTime: v.currentTime, duration: v.duration || 0, paused: v.paused, ended: v.ended };
  });
}

/**
 * Drives playback in the host's Chrome tab and publishes the video element's
 * state, so the headset can draw its own controls and never needs to see the
 * service's UI. Emits 'state' with a PlaybackState on every change.
 */
export class Player extends EventEmitter<{ state: [PlaybackState] }> {
  #chrome: ChromeHost;
  #service: ServiceAdapter | undefined;
  #state: PlaybackState = { status: 'idle', position: 0, duration: 0 };
  #poll: NodeJS.Timeout | undefined;
  // Bumped on every play/stop so a superseded play() doesn't clobber state.
  #generation = 0;
  #missedPolls = 0;

  constructor(chrome: ChromeHost) {
    super();
    this.#chrome = chrome;
  }

  get state(): PlaybackState {
    return this.#state;
  }

  /**
   * Starts loading a title and returns immediately; follow progress via
   * 'state'. Throws PageBusyError synchronously if a catalog refresh holds
   * the browser tab.
   */
  play(service: ServiceAdapter, watchUrl: string, title?: string): void {
    this.#chrome.claim('playback');
    const generation = ++this.#generation;
    this.#stopPolling();
    this.#service = service;
    this.#set({ status: 'loading', service: service.id, title, watchUrl, position: 0, duration: 0, error: undefined });
    void this.#load(service, watchUrl, generation);
  }

  async #load(service: ServiceAdapter, watchUrl: string, generation: number): Promise<void> {
    try {
      const page = await this.#chrome.page();
      await page.bringToFront();
      await page.goto(watchUrl, { waitUntil: 'domcontentloaded' });
      if (service.playerCss) await page.addStyleTag({ content: service.playerCss });
      await page.waitForFunction(
        () => {
          const v = document.querySelector('video');
          return !!v && !v.paused && v.currentTime > 0;
        },
        null,
        { timeout: START_TIMEOUT_MS, polling: 250 },
      );
      if (generation !== this.#generation) return;
      this.#set({ status: 'playing' });
      this.#startPolling(page, generation);
    } catch (err) {
      if (generation !== this.#generation) return;
      this.#fail(err instanceof Error ? err.message : String(err));
    }
  }

  async stop(): Promise<void> {
    this.#generation++;
    this.#stopPolling();
    try {
      const page = await this.#chrome.page();
      await page.goto('about:blank');
    } finally {
      // Even if Chrome is unreachable, the session is over as far as clients
      // and the tab lease are concerned.
      this.#service = undefined;
      this.#chrome.release('playback');
      this.#state = { status: 'idle', position: 0, duration: 0 };
      this.emit('state', this.#state);
    }
  }

  async toggle(): Promise<void> {
    const page = await this.#activePage();
    if (this.#service?.togglePlayback) await this.#service.togglePlayback(page);
    else await page.keyboard.press('Space');
    await this.#sample(page, this.#generation);
  }

  async setPaused(paused: boolean): Promise<void> {
    const video = await readVideo(await this.#activePage());
    if (video && video.paused !== paused) await this.toggle();
  }

  async seekBy(seconds: number): Promise<void> {
    const page = await this.#activePage();
    if (this.#service?.seekTo) {
      const video = await readVideo(page);
      if (video) await this.#service.seekTo(page, Math.max(0, video.currentTime + seconds));
    } else {
      // Fallback: most players seek ~10s per arrow press.
      const key = seconds < 0 ? 'ArrowLeft' : 'ArrowRight';
      for (let i = 0; i < Math.max(1, Math.round(Math.abs(seconds) / 10)); i++) await page.keyboard.press(key);
    }
    await this.#sample(page, this.#generation);
  }

  async seekTo(seconds: number): Promise<void> {
    const page = await this.#activePage();
    if (!this.#service?.seekTo) throw new Error(`${this.#service?.name} does not support absolute seeking`);
    await this.#service.seekTo(page, seconds);
    await this.#sample(page, this.#generation);
  }

  async #activePage(): Promise<Page> {
    if (!this.#service || this.#state.status === 'idle' || this.#state.status === 'error') {
      throw new Error('Nothing is playing');
    }
    return this.#chrome.page();
  }

  #startPolling(page: Page, generation: number): void {
    this.#missedPolls = 0;
    this.#poll = setInterval(() => this.#sample(page, generation), POLL_MS);
  }

  /** Reads the video element into state. Also called right after controls so clients see the effect immediately. */
  async #sample(page: Page, generation: number): Promise<void> {
    let video: VideoSnapshot | null = null;
    try {
      video = await readVideo(page);
    } catch {
      // Page mid-navigation or Chrome gone; treated like a missing video below.
    }
    if (generation !== this.#generation) return;
    if (!video) {
      if (++this.#missedPolls >= LOST_VIDEO_POLLS) {
        this.#stopPolling();
        this.#fail('Playback stopped on the host (the video went away)');
      }
      return;
    }
    this.#missedPolls = 0;
    const status: PlaybackStatus = video.ended ? 'ended' : video.paused ? 'paused' : 'playing';
    this.#set({ status, position: video.currentTime, duration: video.duration });
  }

  /** Ends the session in an error state and frees the tab for catalog refreshes. */
  #fail(message: string): void {
    this.#chrome.release('playback');
    this.#set({ status: 'error', error: message });
  }

  #stopPolling(): void {
    clearInterval(this.#poll);
    this.#poll = undefined;
  }

  #set(patch: Partial<PlaybackState>): void {
    const next = { ...this.#state, ...patch };
    const changed = (Object.keys(next) as (keyof PlaybackState)[]).some((k) => next[k] !== this.#state[k]);
    this.#state = next;
    if (changed) this.emit('state', next);
  }
}
