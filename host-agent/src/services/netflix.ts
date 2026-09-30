import { NotLoggedInError, type CatalogRow, type ServiceAdapter } from './types.ts';

// Netflix DOM selectors. Best-effort as of writing; verify against the live
// site on the host and update here when Netflix changes its markup.
const sel = {
  row: '.lolomoRow',
  rowTitle: '.row-header-title',
  card: '.slider-item .title-card',
  profileGate: '.profile-gate-container, .list-profiles',
};

const watchUrlPattern = /^https:\/\/www\.netflix\.com\/watch\/\d+(\?.*)?$/;

export const netflix: ServiceAdapter = {
  id: 'netflix',
  name: 'Netflix',

  async fetchCatalog(page) {
    await page.goto('https://www.netflix.com/browse', { waitUntil: 'domcontentloaded' });
    if (page.url().includes('/login') || (await page.locator(sel.profileGate).count()) > 0) {
      throw new NotLoggedInError(this.name);
    }
    await page.locator(sel.row).first().waitFor({ timeout: 20_000 });

    // Rows lazy-load as you scroll.
    for (let i = 0; i < 8; i++) {
      await page.mouse.wheel(0, 2000);
      await page.waitForTimeout(400);
    }

    const rows: CatalogRow[] = await page.evaluate((sel) => {
      return [...document.querySelectorAll(sel.row)].map((row) => {
        const seen = new Set<string>();
        const items = [...row.querySelectorAll(sel.card)].flatMap((card) => {
          const href = card.querySelector('a[href*="/watch/"]')?.getAttribute('href');
          const id = href?.match(/\/watch\/(\d+)/)?.[1];
          // The slider clones cards for infinite scrolling; keep the first.
          if (!id || seen.has(id)) return [];
          seen.add(id);
          const img = card.querySelector('img');
          const title = card.querySelector('a')?.getAttribute('aria-label') ?? img?.alt ?? '';
          return [{ id, title, image: img?.src, watchUrl: `https://www.netflix.com/watch/${id}` }];
        });
        return { title: row.querySelector(sel.rowTitle)?.textContent?.trim() ?? '', items };
      });
    }, sel);

    await page.goto('about:blank');
    return rows.filter((r) => r.items.length > 0);
  },

  isWatchUrl(url) {
    return watchUrlPattern.test(url);
  },

  playerCss: `
    [data-uia="controls-standard"],
    .watch-video--bottom-controls-container,
    .watch-video--back-container,
    .watch-video--flag-container { display: none !important; }
    * { cursor: none !important; }
  `,

  async seekTo(page, seconds) {
    // Setting video.currentTime directly makes Netflix error out (M7375),
    // so go through the player API its own UI uses.
    await page.evaluate((ms) => {
      const videoPlayer = (window as any).netflix.appContext.state.playerApp.getAPI().videoPlayer;
      const sessionId = videoPlayer.getAllPlayerSessionIds()[0];
      videoPlayer.getVideoPlayerBySessionId(sessionId).seek(ms);
    }, Math.round(seconds * 1000));
  },
};
