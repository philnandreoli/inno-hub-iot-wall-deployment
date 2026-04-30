import { useEffect, useRef, useState } from 'react'
import mermaid from 'mermaid'

const DIAGRAM_DEFINITION = `
%%{init: {
  'theme': 'dark',
  'themeVariables': {
    'primaryColor': '#0f1a2e',
    'primaryTextColor': '#e0f0ff',
    'primaryBorderColor': '#00e5ff',
    'lineColor': '#00b8cc',
    'secondaryColor': '#1a2845',
    'tertiaryColor': '#0c1424',
    'edgeLabelBackground': '#070d1a',
    'clusterBkg': '#0c1424',
    'clusterBorder': '#00e5ff',
    'titleColor': '#00e5ff',
    'nodeTextColor': '#e0f0ff'
  }
}}%%
flowchart TB
    User["\`**USER**
Web Browser\`"]

    subgraph cloud ["AZURE CLOUD"]
        direction LR
        Entra["\`**ENTRA ID**
OAuth 2.0 + OIDC\`"]
        Frontend["\`**REACT + NGINX**
Vite SPA\`"]
        Backend["\`**FASTAPI**
Python Backend\`"]
        EventGrid["\`**EVENT GRID**
MQTT Broker\`"]
        Fabric["\`**FABRIC**
Eventhouse KQL\`"]
        AppInsights["\`**APP INSIGHTS**
Telemetry\`"]
    end

    subgraph edge ["EDGE SITE // ARC-ENABLED K3S"]
        AIO["\`**AZURE IOT OPERATIONS**
Data Flow + MQTT Broker\`"]
    end

    subgraph ot ["OT NETWORK // INDUSTRIAL"]
        direction LR
        Beckhoff["\`**BECKHOFF PLC**
Controller\`"]
        Leuze["\`**LEUZE**
Sensor\`"]
        Actuators["\`**ACTUATORS**
Lamp + Fan\`"]
    end

    User == "authenticate" ==> Entra
    User == "browse" ==> Frontend
    Frontend -.-> AppInsights
    Frontend == "API calls" ==> Backend

    Backend == "C2D: MQTT v5 command" ==> EventGrid
    Backend == "D2C: KQL status query" ==> Fabric

    EventGrid == "C2D: publish command" ==> AIO

    AIO == "D2C: telemetry + status" ==> Fabric

    AIO == "C2D: OPC UA write" ==> Beckhoff
    Beckhoff == "D2C: OPC UA read" ==> AIO
    AIO == "D2C: OPC UA read" ==> Leuze
    Beckhoff ==> Actuators

    classDef userNode fill:#0f1a2e,stroke:#00e5ff,stroke-width:2px,color:#00e5ff
    classDef cloudNode fill:#0f1a2e,stroke:#00e5ff,stroke-width:1.5px,color:#e0f0ff
    classDef edgeNode fill:#1a2845,stroke:#ffab00,stroke-width:2px,color:#e0f0ff
    classDef otNode fill:#1a2845,stroke:#00e676,stroke-width:1.5px,color:#e0f0ff

    class User userNode
    class Entra,Frontend,Backend,EventGrid,Fabric,AppInsights cloudNode
    class AIO edgeNode
    class Beckhoff,Leuze,Actuators otNode

    style cloud fill:#070d1a,stroke:#00e5ff,stroke-width:2px,color:#00e5ff
    style edge fill:#070d1a,stroke:#ffab00,stroke-width:2px,color:#ffab00
    style ot fill:#070d1a,stroke:#00e676,stroke-width:2px,color:#00e676

    linkStyle 0,1,3 stroke:#00b8cc,stroke-width:2.5px
    linkStyle 4,6,8 stroke:#ff1744,stroke-width:2.5px
    linkStyle 5,7,9,10 stroke:#00e676,stroke-width:2.5px
    linkStyle 2 stroke:#7a9cc0,stroke-width:1.5px,stroke-dasharray:6
    linkStyle 11 stroke:#7a9cc0,stroke-width:2px
`

const LEGEND_ITEMS = [
  { color: '#ff1744', label: 'C2D — Cloud-to-Device (Command & Control)' },
  { color: '#00e676', label: 'D2C — Device-to-Cloud (Telemetry & Status)' },
  { color: '#00b8cc', label: 'User / Auth / Frontend flows' },
  { color: '#7a9cc0', label: 'Telemetry & observability', dashed: true },
]

export function ArchitectureDiagram({ onBack }) {
  const containerRef = useRef(null)
  const [rendered, setRendered] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => {
    let cancelled = false

    mermaid.initialize({
      startOnLoad: false,
      theme: 'dark',
      securityLevel: 'strict',
      fontFamily: 'Rajdhani, sans-serif',
    })

    async function render() {
      try {
        const id = 'arch-diagram-' + Date.now()
        const { svg } = await mermaid.render(id, DIAGRAM_DEFINITION)
        if (!cancelled && containerRef.current) {
          const parser = new DOMParser()
          const svgDoc = parser.parseFromString(svg, 'image/svg+xml')
          const svgEl = svgDoc.documentElement
          // Make SVG responsive
          svgEl.removeAttribute('height')
          svgEl.style.width = '100%'
          svgEl.style.maxWidth = '1200px'
          svgEl.style.height = 'auto'
          containerRef.current.replaceChildren(svgEl)
          setRendered(true)
        }
      } catch (e) {
        if (!cancelled) setError(e.message)
      }
    }

    render()
    return () => { cancelled = true }
  }, [])

  return (
    <div className="arch-page">
      {/* Back navigation */}
      <button type="button" className="arch-back-btn" onClick={onBack}>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polyline points="15 18 9 12 15 6" />
        </svg>
        Back to Dashboard
      </button>

      {/* Page header */}
      <div className="arch-header">
        <span className="arch-label">// System Overview</span>
        <h1 className="arch-title">Solution Architecture</h1>
        <p className="arch-subtitle">
          End-to-end data flow across Azure Cloud, Edge, and OT Network layers
        </p>
      </div>

      {/* Legend */}
      <div className="arch-legend">
        {LEGEND_ITEMS.map((item) => (
          <div className="arch-legend-item" key={item.label}>
            <span
              className={`arch-legend-line${item.dashed ? ' dashed' : ''}`}
              style={{ backgroundColor: item.color }}
            />
            <span className="arch-legend-text">{item.label}</span>
          </div>
        ))}
      </div>

      {/* Main layout: descriptions left, diagram right */}
      <div className="arch-body">
        <div className="arch-sidebar">
          {/* Global deployment callout */}
          <div className="arch-callout">
            <div className="arch-callout-icon">
              <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="var(--cyan)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <path d="M2 12h20" />
                <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" />
              </svg>
            </div>
            <div className="arch-callout-stat">40+</div>
            <div className="arch-callout-label">IoT Walls Deployed Globally</div>
            <p className="arch-callout-desc">
              Each edge site runs its own Azure IoT Operations instance on Arc-enabled Kubernetes,
              connecting industrial PLCs and sensors to the Azure cloud for real-time command
              and control across every location.
            </p>
          </div>

          {/* Flow descriptions */}
          <div className="arch-flow-card c2d">
            <div className="arch-flow-icon">
              <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#ff1744" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <line x1="12" y1="5" x2="12" y2="19" />
                <polyline points="19 12 12 19 5 12" />
              </svg>
            </div>
            <h3>Cloud-to-Device</h3>
            <p>
              Commands flow from the React UI through the FastAPI backend, which publishes MQTT v5
              messages to Azure Event Grid. IoT Operations Data Flow bridges them to the internal
              MQTT broker, delivering OPC UA writes to Beckhoff PLCs that control lamps and fans.
            </p>
          </div>
          <div className="arch-flow-card d2c">
            <div className="arch-flow-icon">
              <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#00e676" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <line x1="12" y1="19" x2="12" y2="5" />
                <polyline points="5 12 12 5 19 12" />
              </svg>
            </div>
            <h3>Device-to-Cloud</h3>
            <p>
              Beckhoff and Leuze devices publish telemetry and status confirmations to the internal
              MQTT broker. IoT Operations Data Flow routes this data to Microsoft Fabric Eventhouse,
              where the backend queries it via KQL to display live device status in the dashboard.
            </p>
          </div>
        </div>

        {/* Diagram */}
        <div className="arch-diagram-wrapper">
          {!rendered && !error && (
            <div className="arch-loading">
              <div className="spinner" />
              <span>Rendering diagram…</span>
            </div>
          )}
          {error && (
            <div className="arch-error">
              <p>Failed to render diagram</p>
              <code>{error}</code>
            </div>
          )}
          <div
            ref={containerRef}
            className={`arch-diagram-container${rendered ? ' visible' : ''}`}
          />
        </div>
      </div>
    </div>
  )
}
