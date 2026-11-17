import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';
import icon from 'astro-icon';
import astrowind from './vendor/integration';

export default defineConfig({
  output: 'static',
  devToolbar: { enabled: false },
  integrations: [sitemap(), icon({ include: { tabler: ['*'] } }), astrowind({ config: './src/config.yaml' })],
  vite: {
    server: { watch: { usePolling: true, interval: 350 } },
    plugins: [tailwindcss()],
    resolve: { alias: { '~': path.join(path.dirname(fileURLToPath(import.meta.url)), 'src') } },
  },
});
