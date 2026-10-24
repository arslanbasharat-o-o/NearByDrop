import { fileURLToPath } from "node:url"
import { defineConfig } from "vite"

export default defineConfig({
  base: "./",
  resolve: {
    alias: { "@": fileURLToPath(new URL(".", import.meta.url)) },
  },
  build: {
    outDir: "docs/assets",
    emptyOutDir: false,
    rollupOptions: {
      input: "scripts/site-components.tsx",
      output: {
        entryFileNames: "site-components.js",
        chunkFileNames: "[name].js",
        assetFileNames: "[name][extname]",
      },
    },
  },
})
