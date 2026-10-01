// API and security behaviour of a real agent driving headless Chromium with
// the Demo service. Run: npm test (CHROME_PATH=... to pick the browser).
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { setTimeout as sleep } from 'node:timers/promises';
import { chromium } from 'playwright-core';
import WebSocket from 'ws';

const PORT = 8797;
const CDP_PORT = 9335;
const base = `http://127.0.0.1:${PORT}`;
const demoUrl = 'https://download.blender.org/durian/trailer/sintel_trailer-1080p.mp4';
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'stream-frame-agent-'));

let agent: ChildProcess;
let token = '';

const auth = () => ({ authorization: `Bearer ${token}` });
const json = { 'content-type': 'application/json' };

function post(pathname: string, body: unknown, headers: Record<string, string> = {}) {
  return fetch(base + pathname, { method: 'POST', headers: { ...auth(), ...json, ...headers }, body: JSON.stringify(body) });
}

async function state(): Promise<any> {
  return (await fetch(`${base}/api/state`, { headers: auth() })).json();
}

async function waitForStatus(status: string, timeoutMs = 30_000): Promise<any> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const s = await state();
    if (s.status === status) return s;
    await sleep(200);
  }
  assert.fail(`status never became ${status} (now ${(await state()).status})`);
}

/** Raw request, so the Host header can be forged (fetch won't allow it). */
function rawGet(pathname: string, headers: Record<string, string>): Promise<number> {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port: PORT, path: pathname, headers }, (res) => {
      res.resume();
      resolve(res.statusCode ?? 0);
    }).on('error', reject);
  });
}

before(async () => {
  agent = spawn(process.execPath, ['src/main.ts'], {
    cwd: path.join(import.meta.dirname, '..'),
    stdio: 'ignore',
    env: {
      ...process.env,
      PORT: String(PORT),
      CDP_PORT: String(CDP_PORT),
      DATA_DIR: dataDir,
      CHROME_PATH: process.env.CHROME_PATH ?? 'chromium',
      KIOSK: '0',
      CHROME_ARGS: '--headless=new --mute-audio',
      AGENT_TOKEN: '', // exercise the generated token
    },
  });
  for (let i = 0; i < 80; i++) {
    try {
      token = fs.readFileSync(path.join(dataDir, 'token'), 'utf8').trim();
      if ((await fetch(`${base}/api/services`, { headers: auth() })).ok) return;
    } catch {
      // not up yet
    }
    await sleep(250);
  }
  throw new Error('agent did not start');
});

after(async () => {
  agent.kill();
  try {
    const browser = await chromium.connectOverCDP(`http://127.0.0.1:${CDP_PORT}`);
    await (await browser.newBrowserCDPSession()).send('Browser.close');
  } catch {
    // already gone
  }
  fs.rmSync(dataDir, { recursive: true, force: true });
});

test('generates a private token when AGENT_TOKEN is unset, and requires it', async () => {
  assert.ok(token.length >= 20);
  if (process.platform !== 'win32') {
    assert.equal(fs.statSync(path.join(dataDir, 'token')).mode & 0o777, 0o600);
  }
  assert.equal((await fetch(`${base}/api/services`)).status, 401);
  assert.equal((await fetch(`${base}/api/services`, { headers: { authorization: 'Bearer wrong' } })).status, 401);
  assert.equal((await fetch(`${base}/api/services?token=${token}`)).status, 200);
});

test('refuses non-JSON POSTs, so cross-site pages cannot send simple requests', async () => {
  const res = await fetch(`${base}/api/control`, {
    method: 'POST',
    headers: { ...auth(), 'content-type': 'text/plain' },
    body: '{"action":"stop"}',
  });
  assert.equal(res.status, 415);
});

test('refuses cross-origin API calls and unknown Host headers (DNS rebinding)', async () => {
  assert.equal((await post('/api/control', { action: 'stop' }, { origin: 'https://evil.example' })).status, 403);
  assert.equal((await post('/api/control', { action: 'stop' }, { origin: base })).status, 200);
  assert.equal(await rawGet('/api/services', { host: `evil.example:${PORT}`, ...auth() }), 403);
  assert.equal(await rawGet('/api/services', { host: `localhost:${PORT}`, ...auth() }), 200);
});

test('refuses WebSocket upgrades from other origins', async () => {
  const connect = (origin?: string) =>
    new Promise<boolean>((resolve) => {
      const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws?token=${token}`, origin ? { origin } : {});
      ws.on('message', () => {
        ws.close();
        resolve(true);
      });
      ws.on('error', () => resolve(false));
    });
  assert.equal(await connect('https://evil.example'), false);
  assert.equal(await connect(), true);
});

test('rejects missing or non-numeric seek values', async () => {
  for (const body of [{ action: 'seekTo' }, { action: 'seekTo', value: 'abc' }, { action: 'seekBy', value: null }]) {
    assert.equal((await post('/api/control', body)).status, 400, JSON.stringify(body));
  }
});

test('playback and catalog refresh share the tab without trampling each other', async () => {
  assert.equal((await fetch(`${base}/api/catalog/demo`, { headers: auth() })).status, 200, 'prime the cache');
  assert.equal((await post('/api/play', { service: 'demo', watchUrl: demoUrl })).status, 202);
  await waitForStatus('playing');
  const refresh = await fetch(`${base}/api/catalog/demo?refresh`, { headers: auth() });
  assert.equal(refresh.status, 409);
  assert.equal((await fetch(`${base}/api/catalog/demo`, { headers: auth() })).status, 200, 'cache still served');

  // The site navigates away from the player: the session must end rather
  // than freeze at "playing", and the tab must be free again.
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${CDP_PORT}`);
  await browser.contexts()[0].pages()[0].goto('about:blank');
  await browser.close();
  const ended = await waitForStatus('error', 15_000);
  assert.match(ended.error, /went away/);
  assert.equal((await fetch(`${base}/api/catalog/demo?refresh`, { headers: auth() })).status, 200);

  assert.equal((await post('/api/control', { action: 'stop' })).status, 200);
  assert.equal((await state()).status, 'idle');
});
