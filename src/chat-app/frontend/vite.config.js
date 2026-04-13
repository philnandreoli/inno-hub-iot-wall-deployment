import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      // Forward /api/* requests to the FastAPI backend on port 5000.
      '/api': {
        target: 'http://localhost:5000',
        changeOrigin: true,
      },
      // Forward /health to backend for easy liveness checks from the browser.
      '/health': {
        target: 'http://localhost:5000',
        changeOrigin: true,
      },
    },
  },
})
