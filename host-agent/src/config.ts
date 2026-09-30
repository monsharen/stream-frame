import os from 'node:os';
import path from 'node:path';

function defaultChromePath(): string {
  switch (process.platform) {
    case 'win32':
      return 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
    case 'darwin':
      return '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
    default:
      return 'google-chrome-stable';
  }
}

const env = process.env;
const dataDir = env.DATA_DIR ?? path.join(os.homedir(), '.theater-agent');

export const config = {
  host: env.HOST ?? '0.0.0.0',
  port: Number(env.PORT ?? 8787),
  // When set, every API/WS request must carry it (Bearer header or ?token=).
  token: env.AGENT_TOKEN || undefined,
  dataDir,
  chrome: {
    path: env.CHROME_PATH ?? defaultChromePath(),
    cdpPort: Number(env.CDP_PORT ?? 9222),
    // A dedicated profile: Chrome refuses remote debugging on the default one,
    // and this keeps the streaming logins separate from personal browsing.
    profileDir: env.CHROME_PROFILE_DIR ?? path.join(dataDir, 'chrome-profile'),
    // Top-left of the (virtual) display Sunshine captures, e.g. "1920,0".
    windowPosition: env.WINDOW_POSITION ?? '0,0',
    kiosk: env.KIOSK !== '0',
    extraArgs: env.CHROME_ARGS ? env.CHROME_ARGS.split(' ').filter(Boolean) : [],
  },
};
