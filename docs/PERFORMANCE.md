# Performance

The Steam Frame runs on a battery and a mobile GPU, and in VR a slow frame isn't just lag: the view itself stutters when you turn your head. So the budget is strict: at 90 Hz a frame has **11 ms**, for both eyes, every frame. This page records how the app is measured, what was found, what changed, and what's left.

## How to measure

`frame-app/tools/perf.gd` runs the 3D shell through typical scenes and prints, per scene: GPU time per frame, real (wall-clock) frame time, the worst frame, and how many frames took over 20 ms (hitches you'd feel). For each scene it also switches parts off (the night sky, the water, the UI redraw) to show what each costs, and while a film plays it reports the video player's own timing (render thread per frame, main-thread upload).

```sh
cd frame-app
STREAM_FRAME_MUTE=1 godot --display-driver x11 --disable-vsync \
  --resolution 1920x1920 --path . res://tools/perf.tscn
```

1920×1920 is roughly one eye of the headset. Numbers are for the machine they run on; compare them with each other, not across machines. Measure on a cool, idle machine: a laptop that's hot or busy (e.g. right after the test suite) throttles and reports two to four times worse numbers for everything.

## What was found and fixed

Measured on the development laptop (Intel Haswell iGPU, 4 cores), one eye's worth of pixels.

| Scene | Before | After |
| --- | --- | --- |
| Watching a film: frame time | 41 ms (24 fps: the app was held to the film's frame rate) | 7 ms; 3 of 180 frames over 20 ms (was 108) |
| Watching a film: GPU | 18.3 ms | 3.8 ms |
| Home: GPU | 9.8 ms | 4.7 ms |
| Opening a catalog: worst frame | 66 ms | 16 ms, none over 20 ms |
| Scrolling the wall: worst frame | 36 ms, 5 frames over 20 ms | 17 ms, none over 20 ms |

### The film held the whole app to its frame rate (fixed)

The built-in player converted every video frame on the main thread (~26 ms per frame here), so rendering waited for it and the app ran at the film's 24 fps: in a headset, juddering head tracking for the whole film. Now a render thread converts and measures each frame (the picture area and colours for the glow) and hands it over; the main thread only uploads it, sharing the buffer rather than copying it. (`native/mpv/src/mpv_player.cpp`)

### Films lagged after a few minutes on older machines (fixed)

On a 2014 MacBook Pro, films ran fine at first, then the fan came on and the frame rate fell. The cause wasn't the app's own work (converting a frame takes ~6 ms on its own thread) but decoding: the Open movies films are VP9, which that machine's GPU can't decode, so mpv decodes every 1080p frame on the CPU (117% of a core for the whole app). After a few minutes the laptop heats up, throttles, and falls behind.

Now the player watches for that: if it's decoding in software and dropping frames, it switches to the provider's lighter version at the same position (for Open movies, Commons' 720p: 68% of a core, about 40% less), and remembers it, so later films start there (Extensions → On-device player → Lighter video, which can be switched off again). Providers offer a lighter version through `VideoProvider.lighter_url()`. And mpv now drops late frames at the decoder (`framedrop=decoder+vo`), which saves work instead of falling further behind.

The player's stats (`MpvPlayer.get_stats()`) report how it decodes (`hwdec`, "no" = on the CPU), the codec and dropped frames, alongside its timings. (Earlier timings here counted mpv waiting for each frame's display time as rendering; it no longer waits.)

### Poster images decoded on the main thread (fixed)

Each poster took ~6 ms to decode (JPEG/PNG/SVG) on the main thread; opening or scrolling a catalog decodes dozens, so frames of 35–65 ms. Reading from disk, decoding, resizing, mipmaps and measuring an image's colours (for its glow) now happen on worker threads; the main thread turns at most 6 finished images into textures per frame. Measuring colours no longer reads textures back from the GPU, which stalled it. (`scripts/image_cache.gd`)

### New tiles all in one frame (fixed)

A new catalog made every visible tile in one frame. Now at most 16 per frame; the rest follow a frame or two later (they rise in with the wave anyway). (`scripts/shell/movie_wall.gd`)

### The night sky and water were most of the GPU time (reduced)

The sky shader runs on every sky pixel of both eyes, and the water was computing the full sky again for its reflection. Stars were the biggest part (~70% of the sky): each pixel checked 8 cells of a 3D grid, in two layers. Now:

- **Stars:** one layer on a cube-face grid, 4 checks per pixel (about 4× cheaper), looking the same.
- **Water:** reflects a reduced sky (bright stars, aurora, moon; the ripples hide fine detail anyway).
- **Aurora:** cheaper 2D noise, and skips pixels with no curtain.
- **While a film plays:** the sky is dimmed to 12%; the aurora, Milky Way and faint stars fade out and stop being computed, leaving the GPU to the film.

### The UI redrew every frame during films (fixed)

The 1920×1080 interface layer was redrawn every frame even while a film played with its controls faded out: memory bandwidth, which on a mobile GPU is battery. It now pauses while nothing of it shows and resumes the moment the controls are needed.

### Headset settings (set, to verify on the Frame)

- **Refresh rate:** the app asks for 90 Hz (the highest offered up to 90) rather than the panel's maximum: smooth, and lighter on the battery than 120–144 Hz.
- **Foveated rendering:** medium, dynamic, eye-tracked where available (`xr/openxr/foveation_*`): the edges of your view render at lower resolution where you can't tell. Godot enables it through OpenXR when the runtime supports it; otherwise it does nothing.
- **Poster mipmaps:** distant posters read small copies: less bandwidth, no shimmer.

## What's left, by impact

1. **Check hardware decoding on the Frame (most important).** `hwdec=auto-copy-safe` falls back to software decoding when the GPU decoder isn't usable, and that is the single biggest cost while watching (see above). Play an Open movies film (VP9) and an H.264 one and check `MpvPlayer.get_stats()["hwdec"]` there; if it's "no", find the hwdec mode the Frame supports (e.g. `v4l2m2m-copy`) and set it.
2. **The video path still copies frames through the CPU.** Even with hardware decoding, each frame is copied back to the CPU, converted (~6 ms, its own thread) and uploaded again by the main thread (~3–5 ms per video frame). Rendering through mpv's OpenGL API straight into the screen's texture would remove all three. Worth it for battery while watching, and the riskiest change (it shares Godot's GL context), so do it and measure it on the Frame itself.
3. **The first seconds of a film** still show some slow frames on the laptop while mpv fills its buffer (20 s read-ahead), competing for 4 cores; later it's smooth. Check on the Frame (8 cores); if it shows, a smaller read-ahead would spread that work out.
4. **Measure on the headset**: the harness, plus SteamVR's frame timing, with foveation and the refresh rate confirmed active. If the GPU is the limit there, the sky has room to go cheaper still (e.g. the aurora at quarter resolution).
5. **Compressed poster textures** (ASTC) would cut GPU memory and bandwidth further; compressing at runtime costs CPU, so only if memory or bandwidth shows up on the headset.
