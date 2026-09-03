import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router'
import { AuthProvider } from '../core/auth/AuthProvider'
import { ErrorBoundary } from '../core/erros/ErrorBoundary'
import { supabaseConfigurado } from '../core/supabase/client'
import { Alerta } from '../core/ui/Alerta'
import { router } from './router'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, staleTime: 30_000, refetchOnWindowFocus: false } },
})

export function App() {
  if (!supabaseConfigurado) {
    return (
      <div className="mx-auto mt-16 max-w-lg p-6">
        <Alerta tipo="erro" titulo="Supabase não configurado">
          Defina <code>VITE_SUPABASE_URL</code> e <code>VITE_SUPABASE_ANON_KEY</code> em <code>.env.local</code> (veja <code>.env.example</code>).
        </Alerta>
      </div>
    )
  }

  return (
    <ErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <RouterProvider router={router} />
        </AuthProvider>
      </QueryClientProvider>
    </ErrorBoundary>
  )
}
