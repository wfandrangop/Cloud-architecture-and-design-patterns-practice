import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// En desarrollo, Vite hace de reverse proxy hacia el backend local (igual que Nginx en AWS).
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': process.env.API_UPSTREAM ?? 'http://localhost:8080',
    },
  },
})
