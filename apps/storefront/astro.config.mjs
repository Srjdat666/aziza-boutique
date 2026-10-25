import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

const site = process.env.PUBLIC_SITE_URL || 'https://srjdat666.github.io';

export default defineConfig({
  site,
  outDir: 'dist',
  build: {
    format: 'directory',
  },
  integrations: [
    sitemap({
      filter: (page) => !page.includes('/admin'),
    }),
  ],
  vite: {
    resolve: {
      alias: {
        '@aziza/shared': new URL('../../packages/shared/src/index.ts', import.meta.url).pathname,
      },
    },
  },
});
