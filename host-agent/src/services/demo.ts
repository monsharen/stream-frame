import type { ServiceAdapter } from './types.ts';

// DRM-free Blender open movies, for testing the whole pipeline
// (control, capture, streaming) without any account or Widevine.
const poster = (file: string) => `https://upload.wikimedia.org/wikipedia/commons/thumb/${file}/330px-${file.split('/').pop()}`;

const movies = [
  {
    id: 'sintel-trailer',
    title: 'Sintel (trailer)',
    image: poster('8/8f/Sintel_poster.jpg'),
    watchUrl: 'https://download.blender.org/durian/trailer/sintel_trailer-1080p.mp4',
  },
  {
    id: 'sintel',
    title: 'Sintel',
    image: poster('8/8f/Sintel_poster.jpg'),
    watchUrl: 'https://download.blender.org/durian/movies/Sintel.2010.1080p.mkv',
  },
  {
    id: 'tears-of-steel',
    title: 'Tears of Steel',
    image: poster('7/70/Tos-poster.png'),
    watchUrl: 'https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov',
  },
];

export const demo: ServiceAdapter = {
  id: 'demo',
  name: 'Demo (open movies)',
  async fetchCatalog() {
    return [{ title: 'Blender open movies', items: movies }];
  },
  isWatchUrl(url) {
    return movies.some((m) => m.watchUrl === url);
  },
  playerCss: 'video { cursor: none !important; } video::-webkit-media-controls { display: none !important; }',
  async togglePlayback(page) {
    await page.evaluate(() => {
      const video = document.querySelector('video');
      if (video) video.paused ? video.play() : video.pause();
    });
  },
  async seekTo(page, seconds) {
    await page.evaluate((s) => {
      const video = document.querySelector('video');
      if (video) video.currentTime = s;
    }, seconds);
  },
};
