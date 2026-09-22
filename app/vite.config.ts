import { execSync } from 'node:child_process'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

function git(comando: string, fallback: string): string {
  try { return execSync(comando, { encoding: 'utf-8' }).trim() } catch { return fallback }
}

export default defineConfig({
  base: '/painel/',
  plugins: [react(), tailwindcss()],
  define: {
    __APP_VERSION__: JSON.stringify(git('git rev-parse --short HEAD', 'dev')),
    __APP_BUILD_EM__: JSON.stringify(git('git log -1 --format=%cd --date=format:%d/%m %H:%M', '')),
  },
})
