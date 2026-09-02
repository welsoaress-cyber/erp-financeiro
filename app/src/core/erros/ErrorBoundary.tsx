import { Component, type ErrorInfo, type ReactNode } from 'react'
import { Alerta } from '../ui/Alerta'
import { Botao } from '../ui/Botao'

interface Props { children: ReactNode }
interface State { erro: Error | null }

export class ErrorBoundary extends Component<Props, State> {
  state: State = { erro: null }

  static getDerivedStateFromError(erro: Error): State {
    return { erro }
  }

  componentDidCatch(erro: Error, info: ErrorInfo) {
    console.error('Erro não tratado', erro, info)
  }

  render() {
    if (!this.state.erro) return this.props.children
    return (
      <div className="mx-auto mt-16 max-w-lg space-y-4 p-6">
        <Alerta tipo="erro" titulo="Algo deu errado">
          {this.state.erro.message}
        </Alerta>
        <Botao onClick={() => window.location.reload()}>Recarregar</Botao>
      </div>
    )
  }
}
