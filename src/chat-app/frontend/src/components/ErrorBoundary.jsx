import { Component } from 'react'
import { trackException } from '../telemetry.js'

export class ErrorBoundary extends Component {
  constructor(props) {
    super(props)
    this.state = { hasError: false, error: null }
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error }
  }

  componentDidCatch(error, errorInfo) {
    trackException(error, {
      componentStack: errorInfo?.componentStack,
    })
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{ color: '#ff6b6b', fontFamily: 'monospace', padding: '2rem' }}>
          <h2>Something went wrong</h2>
          <pre>{this.state.error?.message}</pre>
          <button
            onClick={() => this.setState({ hasError: false, error: null })}
            style={{
              marginTop: '1rem',
              padding: '0.5rem 1rem',
              background: '#333',
              color: '#fff',
              border: '1px solid #555',
              borderRadius: '4px',
              cursor: 'pointer',
            }}
          >
            Try again
          </button>
        </div>
      )
    }
    return this.props.children
  }
}
