import { defineConfig } from 'astro/config';
import cloudflare from '@astrojs/cloudflare';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://getkindl.ing',
  adapter: cloudflare({
    imageService: 'compile',
  }),
  image: {
    remotePatterns: [{ protocol: 'https' }],
  },
  vite: {
    plugins: [tailwindcss()],
  },
});
