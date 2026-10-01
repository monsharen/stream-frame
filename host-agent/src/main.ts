import { CatalogStore } from './catalog.ts';
import { ChromeHost } from './chrome.ts';
import { config } from './config.ts';
import { Player } from './player.ts';
import { createServer } from './server.ts';

const chrome = new ChromeHost();
const player = new Player(chrome);
const catalogs = new CatalogStore(chrome);
const server = createServer(player, catalogs);

server.listen(config.port, config.host, () => {
  console.log(`[agent] listening on http://${config.host}:${config.port}`);
  console.log(`[agent] remote: http://<this-machine>:${config.port}/?token=${config.token}`);
});

// Warm up Chrome so the first play doesn't pay the launch cost.
chrome.page().catch((err) => console.error('[chrome] could not connect:', err.message));

async function shutdown(): Promise<void> {
  server.close();
  await chrome.close();
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
