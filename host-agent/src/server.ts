import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import http from 'node:http';
import net from 'node:net';
import path from 'node:path';
import { WebSocketServer, type WebSocket } from 'ws';
import type { CatalogStore } from './catalog.ts';
import { PageBusyError } from './chrome.ts';
import { config } from './config.ts';
import type { Player } from './player.ts';
import { getService, services } from './services/index.ts';
import { NotLoggedInError } from './services/types.ts';

const publicDir = path.join(import.meta.dirname, '..', 'public');
const contentTypes: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
};

class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const MAX_BODY_BYTES = 64 * 1024;

function sameSecret(given: string | null | undefined, expected: string): boolean {
  if (!given) return false;
  // Hash first so timingSafeEqual gets equal-length inputs.
  const digest = (v: string) => crypto.createHash('sha256').update(v).digest();
  return crypto.timingSafeEqual(digest(given), digest(expected));
}

function authorized(req: http.IncomingMessage, url: URL): boolean {
  const bearer = req.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
  return sameSecret(bearer, config.token) || sameSecret(url.searchParams.get('token'), config.token);
}

/** Host header must be an IP, localhost or a configured name; blocks DNS rebinding. */
function hostAllowed(req: http.IncomingMessage): boolean {
  const host = req.headers.host;
  if (!host) return false;
  const name = host.startsWith('[') ? host.slice(1, host.indexOf(']')) : host.replace(/:\d+$/, '');
  return net.isIP(name) !== 0 || config.allowedHosts.includes(name.toLowerCase());
}

/** Browsers send Origin on cross-site requests and WebSocket upgrades; only same-origin is allowed. */
function originAllowed(req: http.IncomingMessage): boolean {
  const origin = req.headers.origin;
  if (!origin) return true; // non-browser clients (the headset app) and same-origin GETs
  try {
    return new URL(origin).host === req.headers.host;
  } catch {
    return false;
  }
}

async function readJson(req: http.IncomingMessage): Promise<any> {
  // Requiring a JSON content type means cross-site pages can't send these as
  // "simple" requests; they'd need a CORS preflight, which we never grant.
  if (!req.headers['content-type']?.startsWith('application/json')) {
    throw new HttpError(415, 'Content-Type must be application/json');
  }
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new HttpError(413, 'Request body too large');
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
  } catch {
    throw new HttpError(400, 'Invalid JSON body');
  }
}

function seconds(value: unknown): number {
  const n = typeof value === 'number' ? value : Number.NaN;
  if (!Number.isFinite(n)) throw new HttpError(400, 'value must be a number of seconds');
  return n;
}

function send(res: http.ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

async function serveStatic(res: http.ServerResponse, pathname: string): Promise<void> {
  const file = path.join(publicDir, pathname === '/' ? 'index.html' : pathname);
  if (!file.startsWith(publicDir + path.sep)) throw new HttpError(404, 'Not found');
  try {
    const body = await fs.readFile(file);
    res.writeHead(200, { 'content-type': contentTypes[path.extname(file)] ?? 'application/octet-stream' });
    res.end(body);
  } catch {
    throw new HttpError(404, 'Not found');
  }
}

export function createServer(player: Player, catalogs: CatalogStore): http.Server {
  async function handleApi(req: http.IncomingMessage, res: http.ServerResponse, url: URL): Promise<void> {
    const route = `${req.method} ${url.pathname}`;

    if (route === 'GET /api/services') {
      return send(res, 200, services.map(({ id, name }) => ({ id, name })));
    }

    const catalogMatch = url.pathname.match(/^\/api\/catalog\/([\w-]+)$/);
    if (req.method === 'GET' && catalogMatch) {
      const service = getService(catalogMatch[1]);
      if (!service) throw new HttpError(404, 'Unknown service');
      return send(res, 200, await catalogs.get(service, url.searchParams.has('refresh')));
    }

    if (route === 'GET /api/state') return send(res, 200, player.state);

    if (route === 'POST /api/play') {
      const { service: serviceId, watchUrl, title } = await readJson(req);
      const service = getService(serviceId);
      if (!service) throw new HttpError(404, 'Unknown service');
      if (typeof watchUrl !== 'string' || !service.isWatchUrl(watchUrl)) {
        throw new HttpError(400, `Not a ${service.name} watch URL`);
      }
      // Loading can take a while; the client follows progress over the WebSocket.
      player.play(service, watchUrl, typeof title === 'string' ? title : undefined);
      return send(res, 202, player.state);
    }

    if (route === 'POST /api/control') {
      const { action, value } = await readJson(req);
      switch (action) {
        case 'toggle': await player.toggle(); break;
        case 'play': await player.setPaused(false); break;
        case 'pause': await player.setPaused(true); break;
        case 'seekBy': await player.seekBy(seconds(value)); break;
        case 'seekTo': await player.seekTo(Math.max(0, seconds(value))); break;
        case 'stop': await player.stop(); break;
        default: throw new HttpError(400, `Unknown action: ${action}`);
      }
      return send(res, 200, player.state);
    }

    throw new HttpError(404, 'Not found');
  }

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    try {
      if (!hostAllowed(req)) throw new HttpError(403, 'Unknown Host; add it to ALLOWED_HOSTS');
      if (!url.pathname.startsWith('/api/')) return await serveStatic(res, url.pathname);
      if (!originAllowed(req)) throw new HttpError(403, 'Cross-origin requests are not allowed');
      if (!authorized(req, url)) throw new HttpError(401, 'Missing or wrong token');
      await handleApi(req, res, url);
    } catch (err) {
      const status =
        err instanceof HttpError ? err.status
        : err instanceof NotLoggedInError ? 409
        : err instanceof PageBusyError ? 409
        : 500;
      if (status === 500) console.error(`[http] ${req.method} ${url.pathname}:`, err);
      send(res, status, { error: err instanceof Error ? err.message : String(err) });
    }
  });

  const wss = new WebSocketServer({ noServer: true });
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    if (url.pathname !== '/ws' || !hostAllowed(req) || !originAllowed(req) || !authorized(req, url)) {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws: WebSocket) => {
      ws.send(JSON.stringify({ type: 'state', state: player.state }));
    });
  });
  player.on('state', (state) => {
    const message = JSON.stringify({ type: 'state', state });
    for (const client of wss.clients) client.send(message);
  });

  return server;
}
