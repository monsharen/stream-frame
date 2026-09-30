import type { Page } from 'playwright-core';

export type CatalogItem = {
  id: string;
  title: string;
  image?: string;
  watchUrl: string;
};

export type CatalogRow = {
  title: string;
  items: CatalogItem[];
};

/**
 * Everything service-specific lives behind this interface. Adapters that
 * scrape a site's DOM are inherently fragile; keep selectors in one place
 * per adapter so a site redesign is a one-file fix.
 */
export type ServiceAdapter = {
  id: string;
  name: string;
  /** Reads the catalog from the (already logged-in) browser tab. */
  fetchCatalog(page: Page): Promise<CatalogRow[]>;
  /** Only URLs passing this check may be opened, so the API can't drive the logged-in browser anywhere else. */
  isWatchUrl(url: string): boolean;
  /** Injected once playback starts to hide the site's own player chrome and cursor. */
  playerCss?: string;
  /** Play/pause. Defaults to pressing Space, which the big services all honour. */
  togglePlayback?(page: Page): Promise<void>;
  /** Absolute seek. Without it, only relative seeking via arrow keys is available. */
  seekTo?(page: Page, seconds: number): Promise<void>;
};

export class NotLoggedInError extends Error {
  constructor(service: string) {
    super(`Not logged in to ${service}. Log in once on the host (e.g. via Moonlight) and retry.`);
  }
}
