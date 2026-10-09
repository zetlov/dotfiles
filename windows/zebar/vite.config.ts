import { defineConfig } from 'vite';
import solidPlugin from 'vite-plugin-solid';
import { resolve } from 'node:path';

export default defineConfig({
  base: './',
  build: {
    emptyOutDir: true,
    rollupOptions: {
      input: {
        desktop: resolve(__dirname, 'index.html'),
        surface: resolve(__dirname, 'surface.html'),
      },
    },
    target: 'es2022',
  },
  plugins: [solidPlugin()],
});
