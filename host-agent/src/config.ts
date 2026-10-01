import crypto from 'node:crypto';
import fs from 'node:fs';
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
const dataDir = env.DATA_DIR ?? path.join(os.homedir(), '.stream-frame');

/**
 * The agent drives a logged-in browser, so it always requires a token: the
 * AGENT_TOKEN env var, or one generated on first run and kept in the data dir.
 */
function loadToken(): string {
  if (env.AGENT_TOKEN) return env.AGENT_TOKEN;
  const file = path.join(dataDir, 'token');
  try {
    return fs.readFileSync(file, 'utf8').trim();
  } catch {
    const token = crypto.randomBytes(18).toString('base64url');
    fs.mkdirSync(dataDir, { recursive: true });
    fs.writeFileSync(file, token, { mode: 0o600 });
    return token;
  }
}

export const config = {
  host: env.HOST ?? '0.0.0.0',
  port: Number(env.PORT ?? 8787),
  // Every API/WS request must carry it (Bearer header or ?token=).
  token: loadToken(),
  // Host names (besides IP addresses, localhost and this machine's name) the
  // agent may be addressed by. Anything else is refused to stop DNS rebinding.
  allowedHosts: [
    'localhost',
    os.hostname().toLowerCase(),
    `${os.hostname().toLowerCase()}.local`,
    ...(env.ALLOWED_HOSTS ?? '').toLowerCase().split(',').map((h) => h.trim()).filter(Boolean),
  ],
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
