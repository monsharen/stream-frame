const token = new URLSearchParams(location.search).get('token');
const $ = (id) => document.getElementById(id);

let currentService;
let state = { status: 'idle', position: 0, duration: 0 };
let scrubbing = false;
// Errors from our own actions (not part of the agent's state); they stay
// until the next action succeeds rather than vanishing on the next poll.
let actionError = '';

async function api(path, body) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(path, body ? { method: 'POST', headers, body: JSON.stringify(body) } : { headers });
  const json = await res.json();
  if (!res.ok) throw new Error(json.error ?? res.statusText);
  return json;
}

function formatTime(seconds) {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = String(s % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

function el(tag, props = {}, children = []) {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children);
  return node;
}

async function loadServices() {
  const services = await api('/api/services');
  $('services').replaceChildren(
    ...services.map((s) => el('button', { textContent: s.name, onclick: () => selectService(s.id) }, [])),
  );
  $('services').dataset.ids = services.map((s) => s.id).join(',');
}

async function selectService(id, refresh = false) {
  currentService = id;
  const ids = $('services').dataset.ids.split(',');
  [...$('services').children].forEach((b, i) => b.classList.toggle('active', ids[i] === id));
  $('catalog').replaceChildren(el('p', { className: 'hint', textContent: refresh ? 'Refreshing…' : 'Loading…' }));
  try {
    const catalog = await api(`/api/catalog/${id}${refresh ? '?refresh' : ''}`);
    if (currentService === id) renderCatalog(catalog); // ignore a slow response for a tab we left
  } catch (err) {
    if (currentService === id) $('catalog').replaceChildren(el('p', { className: 'error', textContent: err.message }));
  }
}

function renderCatalog(catalog) {
  if (!catalog.rows.length) {
    $('catalog').replaceChildren(el('p', { className: 'hint', textContent: 'Catalog is empty.' }));
    return;
  }
  $('catalog').replaceChildren(
    ...catalog.rows.map((row) =>
      el('section', { className: 'row' }, [
        el('h2', { textContent: row.title }),
        el('div', { className: 'cards' }, row.items.map((item) =>
          el('button', { className: 'card', title: item.title, onclick: () => play(catalog.service, item) }, [
            el('img', { src: item.image ?? '', alt: '', loading: 'lazy' }),
            el('span', { textContent: item.title }),
          ]),
        )),
      ]),
    ),
  );
}

async function play(service, item) {
  await act(() => api('/api/play', { service, watchUrl: item.watchUrl, title: item.title }));
}

async function control(action, value) {
  await act(() => api('/api/control', { action, value }));
}

async function act(request) {
  try {
    await request();
    actionError = '';
  } catch (err) {
    actionError = err.message;
  }
  renderState();
}

function renderState() {
  const error = actionError || state.error || '';
  $('now-playing').hidden = state.status === 'idle' && !error;
  $('np-title').textContent = state.title ?? '';
  $('np-status').textContent = state.status === 'playing' ? '' : state.status;
  $('toggle').textContent = state.status === 'paused' ? 'Play' : 'Pause';
  $('np-time').textContent = `${formatTime(state.position)} / ${formatTime(state.duration)}`;
  $('np-error').textContent = error;
  $('np-error').hidden = !error;
  if (!scrubbing) {
    $('scrubber').max = String(Math.floor(state.duration));
    $('scrubber').value = String(Math.floor(state.position));
  }
}

function connect() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  const ws = new WebSocket(`${proto}://${location.host}/ws${token ? `?token=${encodeURIComponent(token)}` : ''}`);
  ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    if (msg.type === 'state') {
      state = msg.state;
      renderState();
    }
  };
  ws.onclose = () => setTimeout(connect, 2000);
}

document.querySelectorAll('[data-action]').forEach((button) => {
  button.addEventListener('click', () => {
    const value = button.dataset.value === undefined ? undefined : Number(button.dataset.value);
    control(button.dataset.action, value);
  });
});

$('scrubber').addEventListener('input', () => {
  scrubbing = true;
  $('np-time').textContent = `${formatTime(Number($('scrubber').value))} / ${formatTime(state.duration)}`;
});
$('scrubber').addEventListener('change', async () => {
  await control('seekTo', Number($('scrubber').value));
  scrubbing = false;
});

$('refresh').addEventListener('click', () => currentService && selectService(currentService, true));

await loadServices();
connect();
