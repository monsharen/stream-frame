# Stream Frame design language

Stream Frame should feel like a calm, premium living-room app (think Apple TV) that happens to be in VR. These are the rules the app follows; new views and controls follow them too.

## Principles

- **Content first.** Artwork, logos and the film carry the colour; the interface is quiet greys and white around them.
- **Nothing extra.** If a control, label or heading isn't needed to do the task, it isn't there. Status shows where it's needed, not everywhere: an extension that isn't ready is a greyed-out tile with just its name; selecting it explains what's up.
- **One way to do each thing.** The same action is the same control, in the same place, on the same button, everywhere.
- **Readable at a distance.** This is read a couple of metres away in a headset: generous sizes, short text, high contrast.

## Input: actions, not keys

Everything a button can do is a named **action** (`scripts/input/input_actions.gd`): Back, Select, Play / pause, Back 10 seconds, Forward 10 seconds, Viewing options, Home, Turn left / right. Views never test for a key or button; they react to actions, and any key, gamepad button, mouse button or VR controller button can be bound to any action (Extensions → Controls). Pointing and clicking (gaze, controller ray, trigger, mouse) select what's under the pointer and aren't actions.

| Action | Default bindings |
| --- | --- |
| Back | Escape (always), Back key, gamepad B, mouse back button, controller B/Y |
| Select | Enter, gamepad A (and the trigger / click, by pointing) |
| Play / pause | Space, media play, gamepad X, controller A/X |
| Back / Forward 10 seconds | J / L, media previous / next, gamepad shoulders |
| Viewing options | O, gamepad Y, controller menu |
| Home | Home, gamepad View |
| Turn left / right | Q / E, gamepad right stick (45° per press; in the desktop preview the mouse at a window edge also turns you) |

### Back

Back is the most important button, so it works the same everywhere:

- **Escape is always Back.** It can't be unbound or moved; other bindings can be added.
- **Every view has one back control:** `UiTheme.back_button()`, a round chevron, first in the view's top bar. (In the player the ✕ in the controls is its back control: back there means stop.)
- **All back controls and all Back bindings go through one function,** `main.go_back()`, never per-view key handling. A view emits `back_requested` from its back control.
- **Inner things close first.** A view may implement `handle_back() -> bool` to close something of its own (the player's viewing options, a search) and return true; otherwise Back goes up one level: the film stops; a catalog, info page or the Extensions app gives way to the home. While typing, Back only stops typing.

## Layout

- **Top bar:** back control, then the title. Tools (search, sort, filter) follow; nothing else.
- **The home** is the extension tiles (logos only), six to a row, then Continue watching. Every tile looks the same, ready or not: selecting one that isn't ready explains why. No grouping by how things play; that's the Extensions app's business.
- **One primary action per view,** focused first. Secondary actions are smaller or behind ⋯ (e.g. the player's viewing options).
- **Nothing over the film.** In 3D the player's title and controls are on their own glass panel just below the screen (nearer than it, sized for reading), never over the picture. They fade while you watch and come back when you move.
- **Floating controls.** Controls sit on the room or the film, not on panels; only reading-heavy pages (info, Extensions) have a panel.

## Controls

- **Text buttons:** `UiTheme.button()`: borderless, translucent, rounded (radius 16). Pressed is white with dark text.
- **Icon buttons:** `GlyphButton` (round; play, pause, ±10, ⋯, ✕, back, refresh), drawn as shapes so they're crisp. Over a film they use the dark fill (`dark = true`).
- **On/off:** a pill, solid white when on, faint when off.
- **Text fields:** translucent, no border.

## Focus and hover

There are no focus frames. Whatever is focused or pointed at **comes forward slightly and glows softly in its own colours** (a poster's, an extension's; a neutral light otherwise), and its title brightens. Posters on the wall also tilt towards the pointer. Focus follows the pointer, so gaze, a controller ray and controller navigation all look the same (`FocusHighlight`, `WallTile`).

## Colour and type

- Background near-black; text `#eceef2`; secondary text `#8a8f9c`; errors `#ff6b6b`. No accent colour in the interface (only the pointer dot is yellow).
- Extension tiles: the service's logo on its brand colour, nothing added.
- Sentence case everywhere ("Viewing options", not "Viewing Options"). Short labels; full sentences only for explanations.

## Motion and light

- Quick and soft: hover and focus 0.15 s, view changes 0.25 s, the wall's wave about 0.5 s; ease-out cubic.
- The night: stars, a slow blue-to-violet aurora along the horizon and a low moon behind you, all mirrored in still water. Restrained enough that content stays the brightest thing in view.
- The room responds to what you watch: the night sky dims over 3 s when a film starts and returns when it stops; the screen's glow, floor reflection and room light follow the picture; in menus they stay on, quieter.
