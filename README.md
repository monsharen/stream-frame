# Steam Frame Theater

Watch streaming services on the Steam Frame so it feels native: browse and control on the headset, while playback actually happens in a logged-in Chrome on a PC and is streamed back with Sunshine/Moonlight.

```
 Frame / stand-in ──HTTP/WS──► host-agent ──CDP──► Chrome (logged in, kiosk
   browse + controls           (Node)              on a virtual display)
        ▲                                                │
        └──────────── Moonlight ◄──── Sunshine ◄─────────┘
```

Why this shape: subscription services only decrypt in licensed DRM (Widevine in Chrome). The headset's own Linux/Android environment gets 480p–720p at best, while Chrome on a Windows/macOS host gets more, and its software-DRM output can be screen-captured.

## Roadmap

1. **host-agent + web remote** (this repo, now): control API, catalog, state push, a browser-based remote.
2. **Frame app v1**: native browse UI (Godot), stream opened via Moonlight as a separate process.
3. **Embedded stream**: `moonlight-common-c` decoding inside the app, so one app does everything.
4. **Theater mode**: OpenXR environment around the screen.

## host-agent

See `host-agent/`. Requires Node ≥ 22.18 (runs TypeScript directly, no build step).

```sh
cd host-agent
npm install
AGENT_TOKEN=some-secret npm start      # then open http://<host>:8787/?token=some-secret
```

| Env var | Default | |
|---|---|---|
| `PORT` / `HOST` | `8787` / `0.0.0.0` | API + remote UI |
| `AGENT_TOKEN` | unset | Required on API/WS calls when set. Set it: the agent controls a logged-in browser. |
| `CHROME_PATH` | platform default | Installed Chrome (not Chromium: Chrome ships Widevine) |
| `CHROME_PROFILE_DIR` | `~/.theater-agent/chrome-profile` | Dedicated profile that keeps your streaming logins |
| `WINDOW_POSITION` | `0,0` | Top-left of the display Sunshine captures |
| `KIOSK` | `1` | `0` for a normal window while debugging |
| `CDP_PORT` | `9222` | Chrome DevTools port (Chrome binds it to localhost) |
| `CHROME_ARGS` | | Extra Chrome flags, space-separated |

API:

- `GET /api/services`
- `GET /api/catalog/:service[?refresh]`: cached; refresh is refused while playing (it uses the playback tab)
- `POST /api/play` `{service, watchUrl, title?}`: returns 202; follow progress on the WebSocket
- `POST /api/control` `{action: toggle|play|pause|seekBy|seekTo|stop, value?}`
- `GET /api/state`, and `WS /ws` which pushes `{type: "state", state}` on every change

The **Demo** service plays DRM-free Blender open movies, so the whole pipeline can be tested without an account.

## Windows host setup

1. **Node** 22.18+ LTS and **Google Chrome**.
2. **Virtual display**: install [Virtual Display Driver](https://github.com/VirtualDrivers/Virtual-Display-Driver), add a 1920×1080@60 display. In *Settings → Display*, note where it sits relative to your main monitor (e.g. to the right of a 2560-wide monitor → `WINDOW_POSITION=2560,0`).
3. **Sunshine**: install from [LizardByte](https://github.com/LizardByte/Sunshine), and in its web UI set the output display to the virtual display.
4. **Firewall**: allow inbound TCP 8787 for Node on your private network.
5. **Run** (PowerShell):
   ```powershell
   $env:AGENT_TOKEN = "some-secret"; $env:WINDOW_POSITION = "2560,0"; npm start
   ```
6. **Log in once**: connect with Moonlight, and in the Chrome window on the virtual display log in to Netflix and pick your profile. The login persists in the dedicated profile.
7. **Check capture**: play something from the remote and confirm Moonlight shows video, not black. The agent already disables hardware-secure decryption; if it's still black, try `CHROME_ARGS="--disable-gpu"`.

## macOS host (alternative)

Same agent. Use [BetterDisplay](https://github.com/waydabber/BetterDisplay) for the virtual display, and a virtual audio device such as BlackHole for Sunshine's audio. Use Chrome, not Safari: Safari's FairPlay path can't be captured. First test: play Netflix in Chrome and screen-record it with ⌘⇧5. If the recording shows video, the Mac works as a host.

## Stand-in client (Linux laptop)

- Moonlight: `flatpak install flathub com.moonlight_stream.Moonlight`, then pair with Sunshine.
- Remote: open `http://<host>:8787/?token=some-secret` in a browser.

## Status

- Verified (headless Chromium on Linux, Demo service): launch/attach, catalog, play, pause/play, seek, stop, WebSocket state, token auth, watch-URL allowlist.
- **Not yet verified: the Netflix adapter** (catalog selectors, overlay CSS, player-API seek). It's written against Netflix's known markup but needs a logged-in session to test. Fix it in `host-agent/src/services/netflix.ts`.
