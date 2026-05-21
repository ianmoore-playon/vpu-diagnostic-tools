import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 3000,
    proxy: {
      "/api": "http://localhost:5173",
      "/ws": { target: "ws://localhost:5173", ws: true },
    },
  },
  build: {
    outDir: "dist",
  },
});
