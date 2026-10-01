import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import { chromium, type Browser, type Page } from 'playwright-core';
import { config } from './config.ts';

const cdpUrl = `http://127.0.0.1:${config.chrome.cdpPort}`;

async function cdpReachable(): Promise<boolean> {
  try {
    const res = await fetch(`${cdpUrl}/json/version`);
    return res.ok;
  } catch {
    return false;
  }
}

function launchChrome(): void {
  const { chrome } = config;
  const args = [
    `--remote-debugging-port=${chrome.cdpPort}`,
    `--user-data-dir=${chrome.profileDir}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--autoplay-policy=no-user-gesture-required',
    // Keep Widevine on the software path. Hardware-secure decryption renders
    // video through a protected surface that screen capture sees as black.
    '--disable-features=HardwareSecureDecryption',
    `--window-position=${chrome.windowPosition}`,
    ...(chrome.kiosk ? ['--kiosk'] : []),
    ...chrome.extraArgs,
  ];
  // Detached so Chrome (and its logged-in sessions) survives agent restarts.
  const child = spawn(chrome.path, args, { detached: true, stdio: 'ignore' });
  child.on('error', (err) => console.error(`[chrome] failed to launch ${chrome.path}:`, err.message));
  child.unref();
}

export type PageOwner = 'playback' | 'catalog';

export class PageBusyError extends Error {
  constructor(holder: PageOwner) {
    super(
      holder === 'playback'
        ? 'Something is playing; stop it first. (The cached catalog is still served.)'
        : 'The catalog is being refreshed; try again in a moment.',
    );
  }
}

/**
 * Owns the single Chrome tab that playback happens in (the one Sunshine
 * shows). We launch Chrome ourselves and attach over CDP rather than letting
 * Playwright launch it: Playwright's launch adds automation flags that
 * streaming sites can detect, and its bundled Chromium ships without Widevine.
 *
 * Playback and catalog scraping both drive this tab, so whoever navigates it
 * must hold the lease (claim/release) for as long as they need it.
 */
export class ChromeHost {
  #browser: Browser | undefined;
  #page: Page | undefined;
  #connecting: Promise<Page> | undefined;
  #holder: PageOwner | undefined;

  /** Throws PageBusyError if someone else holds the tab. Re-claiming your own lease is fine. */
  claim(owner: PageOwner): void {
    if (this.#holder && this.#holder !== owner) throw new PageBusyError(this.#holder);
    this.#holder = owner;
  }

  release(owner: PageOwner): void {
    if (this.#holder === owner) this.#holder = undefined;
  }

  page(): Promise<Page> {
    if (this.#page && !this.#page.isClosed()) return Promise.resolve(this.#page);
    this.#connecting ??= this.#connect().finally(() => (this.#connecting = undefined));
    return this.#connecting;
  }

  async #connect(): Promise<Page> {
    // Reuse a live CDP connection; only re-attach when it actually dropped.
    const browser = this.#browser?.isConnected() ? this.#browser : await this.#attach();
    const context = browser.contexts()[0] ?? (await browser.newContext());
    const page = context.pages()[0] ?? (await context.newPage());
    // With several tabs open (restored session, one opened over Moonlight),
    // make sure the one we drive is the one on screen.
    await page.bringToFront();
    this.#page = page;
    return page;
  }

  async #attach(): Promise<Browser> {
    if (!(await cdpReachable())) {
      console.log('[chrome] not running, launching');
      launchChrome();
      for (let i = 0; i < 60 && !(await cdpReachable()); i++) await sleep(250);
    }
    const browser = await chromium.connectOverCDP(cdpUrl);
    browser.on('disconnected', () => {
      this.#browser = undefined;
      this.#page = undefined;
    });
    this.#browser = browser;
    return browser;
  }

  async close(): Promise<void> {
    // Disconnects the CDP session only; Chrome itself keeps running.
    await this.#browser?.close();
  }
}
