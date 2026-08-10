import { defineConfig } from 'vite';
import solidPlugin from 'vite-plugin-solid';

export default defineConfig({
  base: './',
  build: {
    emptyOutDir: true,
    target: 'es2022',
  },
  plugins: [solidPlugin()],
});
