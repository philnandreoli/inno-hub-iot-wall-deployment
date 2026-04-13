import { useState } from 'react'
import './App.css'

/**
 * App – placeholder shell for the IoT Wall Chat interface.
 *
 * This component will be replaced by the full chat UI once the
 * LLM device-operations chat feature is implemented (EPIC-001).
 */
function App() {
  const [health, setHealth] = useState(null)

  async function checkBackend() {
    try {
      const res = await fetch('/health')
      const data = await res.json()
      setHealth(data.status === 'ok' ? '✅ Backend reachable' : '⚠️ Unexpected response')
    } catch {
      setHealth('❌ Backend unreachable – is it running on port 5000?')
    }
  }

  return (
    <div className="app">
      <h1>IoT Wall Chat</h1>
      <p>LLM-powered device operations assistant for Azure IoT Operations.</p>
      <button onClick={checkBackend}>Check backend health</button>
      {health && <p className="health-status">{health}</p>}
    </div>
  )
}

export default App
