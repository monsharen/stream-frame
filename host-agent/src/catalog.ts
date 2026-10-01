import fs from 'node:fs/promises';
import path from 'node:path';
import { PageBusyError, type ChromeHost } from './chrome.ts';
import { config } from './config.ts';
import type { CatalogRow, ServiceAdapter } from './services/types.ts';

export type Catalog = { service: string; fetchedAt: string; rows: CatalogRow[] };

/**
 * Catalogs are scraped from the same Chrome tab that plays video, so they're
 * cached (in memory and on disk) and a refresh needs the tab lease: it's
 * refused while something plays, and playback is refused while it runs.
 */
export class CatalogStore {
  #chrome: ChromeHost;
  #cache = new Map<string, Catalog>();
  // One scrape at a time (they share the tab). A concurrent refresh of the
  // same service, e.g. from the headset and the phone, joins it.
  #inflight: { serviceId: string; promise: Promise<Catalog> } | undefined;

  constructor(chrome: ChromeHost) {
    this.#chrome = chrome;
  }

  async get(service: ServiceAdapter, refresh = false): Promise<Catalog> {
    if (!refresh) {
      const cached = this.#cache.get(service.id) ?? (await this.#readDisk(service.id));
      if (cached) {
        this.#cache.set(service.id, cached);
        return cached;
      }
    }
    if (this.#inflight) {
      if (this.#inflight.serviceId === service.id) return this.#inflight.promise;
      throw new PageBusyError('catalog');
    }
    this.#chrome.claim('catalog');
    const promise = this.#scrape(service).finally(() => {
      this.#inflight = undefined;
      this.#chrome.release('catalog');
    });
    this.#inflight = { serviceId: service.id, promise };
    return promise;
  }

  async #scrape(service: ServiceAdapter): Promise<Catalog> {
    const rows = await service.fetchCatalog(await this.#chrome.page());
    const catalog = { service: service.id, fetchedAt: new Date().toISOString(), rows };
    this.#cache.set(service.id, catalog);
    await fs.mkdir(config.dataDir, { recursive: true });
    await fs.writeFile(this.#file(service.id), JSON.stringify(catalog));
    return catalog;
  }

  #file(serviceId: string): string {
    return path.join(config.dataDir, `catalog-${serviceId}.json`);
  }

  async #readDisk(serviceId: string): Promise<Catalog | undefined> {
    try {
      return JSON.parse(await fs.readFile(this.#file(serviceId), 'utf8'));
    } catch {
      return undefined;
    }
  }
}
