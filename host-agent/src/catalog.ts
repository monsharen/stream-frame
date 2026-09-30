import fs from 'node:fs/promises';
import path from 'node:path';
import type { ChromeHost } from './chrome.ts';
import { config } from './config.ts';
import type { Player } from './player.ts';
import type { CatalogRow, ServiceAdapter } from './services/types.ts';

export type Catalog = { service: string; fetchedAt: string; rows: CatalogRow[] };

export class PlayerBusyError extends Error {
  constructor() {
    super('Cannot refresh the catalog while something is playing; the cached catalog is still served.');
  }
}

/**
 * Catalogs are scraped from the same Chrome tab that plays video, so they're
 * cached (in memory and on disk) and only refreshed while nothing is playing.
 */
export class CatalogStore {
  #chrome: ChromeHost;
  #player: Player;
  #cache = new Map<string, Catalog>();

  constructor(chrome: ChromeHost, player: Player) {
    this.#chrome = chrome;
    this.#player = player;
  }

  async get(service: ServiceAdapter, refresh = false): Promise<Catalog> {
    if (!refresh) {
      const cached = this.#cache.get(service.id) ?? (await this.#readDisk(service.id));
      if (cached) {
        this.#cache.set(service.id, cached);
        return cached;
      }
    }
    if (this.#player.busy) throw new PlayerBusyError();

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
