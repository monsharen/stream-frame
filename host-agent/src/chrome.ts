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

/**
 * Owns the single Chrome tab that playback happens in. We launch Chrome
 * ourselves and attach over CDP rather than letting Playwright launch it:
 * Playwright's launch adds automation flags that streaming sites can detect,
 * and its bundled Chromium ships without Widevine.
 */
export class ChromeHost {
  #browser: Browser | undefined;
  #page: Page | undefined;
  #connecting: Promise<Page> | undefined;

  page(): Promise<Page> {
    if (this.#page && !this.#page.isClosed()) return Promise.resolve(this.#page);
    this.#connecting ??= this.#connect().finally(() => (this.#connecting = undefined));
    return this.#connecting;
  }

  async #connect(): Promise<Page> {
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
    const context = browser.contexts()[0] ?? (await browser.newContext());
    this.#browser = browser;
    this.#page = context.pages()[0] ?? (await context.newPage());
    return this.#page;
  }

  async close(): Promise<void> {
    // Disconnects the CDP session only; Chrome itself keeps running.
    await this.#browser?.close();
  }
}
