import { useState, useEffect, useLayoutEffect, useCallback } from 'react'
import { useIsAuthenticated, useMsal } from '@azure/msal-react'
import { InteractionStatus } from '@azure/msal-browser'
import { Header } from './components/Header.jsx'
import { DeviceGrid } from './components/DeviceGrid.jsx'
import { DeviceMapView } from './components/DeviceMapView.jsx'
import { ViewToggle } from './components/ViewToggle.jsx'
import { DeviceDetailPage } from './components/DeviceDetailPage.jsx'
import { ArchitectureDiagram } from './components/ArchitectureDiagram.jsx'
import { ToastContainer } from './components/ToastContainer.jsx'
import { LoginPage } from './components/LoginPage.jsx'
import { useToast } from './useToast.js'
import { fetchAllDevicesStatus, setMsalInstance } from './api.js'
import { setAuthenticatedUser, clearAuthenticatedUser, trackEvent, trackException } from './telemetry.js'

const POLL_INTERVAL = 30_000 // 30 seconds
const THEME_STORAGE_KEY = 'iot-control-theme'

export default function App() {
  const isAuthenticated = useIsAuthenticated()
  const { instance, inProgress } = useMsal()

  const [devices, setDevices] = useState([])       // from /api/devices/commands/status
  const [statusMap, setStatusMap] = useState({})   // deviceName → record
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [lastUpdated, setLastUpdated] = useState(null)
  const { toasts, addToast } = useToast()
  const [currentPage, setCurrentPage] = useState(1)
  const [selectedDevice, setSelectedDevice] = useState(null)
  const [currentView, setCurrentView] = useState('dashboard')
  const [dashboardView, setDashboardView] = useState('grid') // 'grid' | 'map'
  const [hideOffline, setHideOffline] = useState(false)
  const [theme, setTheme] = useState(() => {
    if (typeof window === 'undefined') return 'dark'
    const stored = window.localStorage.getItem(THEME_STORAGE_KEY)
    return stored === 'light' ? 'light' : 'dark'
  })

  // Hand the MSAL instance to the api module so every fetch gets a Bearer token.
  const [authReady, setAuthReady] = useState(false)
  useEffect(() => {
    if (isAuthenticated) {
      setMsalInstance(instance)
      setAuthReady(true)
      // Set authenticated user for Application Insights tracking
      const account = instance.getActiveAccount()
      if (account) {
        setAuthenticatedUser(
          account.localAccountId || account.homeAccountId,
          account.name || account.username,
        )
      }
    } else {
      clearAuthenticatedUser()
    }
  }, [isAuthenticated, instance])

  useLayoutEffect(() => {
    document.documentElement.setAttribute('data-theme', theme)
    document.documentElement.style.colorScheme = theme
    window.localStorage.setItem(THEME_STORAGE_KEY, theme)
  }, [theme])

  // Build statusMap from the all-devices-status endpoint
  const buildStatusMap = useCallback((statusPayload) => {
    const map = {}
    const list = statusPayload?.devices ?? []
    for (const item of list) {
      // Try all possible name fields
      const names = [
        item.iotInstanceName,
        item.deviceName,
        item.DeviceName,
        item.device_name,
        item.Device,
        item.device,
        item.name,
        item.Name,
      ].filter(n => n && typeof n === 'string')
      
      // Index by all variations (original and lowercase)
      for (const name of names) {
        map[name] = item
        map[name.toLowerCase()] = item
      }
    }
    return map
  }, [])

  const loadData = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const statusPayload = await fetchAllDevicesStatus()
      setDevices(statusPayload.devices ?? [])
      setStatusMap(buildStatusMap(statusPayload))
      setLastUpdated(new Date())
    } catch (e) {
      setError(e.message)
      trackException(e, { source: 'loadData' })
    } finally {
      setLoading(false)
    }
  }, [buildStatusMap])

  // Initial load — wait until auth is ready so the token is available
  useEffect(() => {
    if (authReady) loadData()
  }, [authReady, loadData])

  // Auto-refresh poll — only start after auth is ready
  useEffect(() => {
    if (!authReady) return
    const id = setInterval(loadData, POLL_INTERVAL)
    return () => clearInterval(id)
  }, [authReady, loadData])

  // Helper to get device name
  const getDeviceName = (device) => {
    if (!device) return 'Unknown'
    let name = device.iotInstanceName ?? device.deviceName ?? device.DeviceName ?? device.device_name ?? device.Device ?? device.device ?? device.name ?? device.Name ?? null
    if (!name) {
      for (const [key, val] of Object.entries(device)) {
        if (typeof val === 'string' && val.length > 0 && !key.toLowerCase().includes('hub')) {
          name = val
          break
        }
      }
    }
    return name || 'Unknown'
  }

  // Derived stats
  const totalDevices = devices.length
  const hubs = new Set(
    devices.map(d => d.hubName ?? d.HubName ?? d.hub ?? d.Hub ?? ''),
  ).size
  const lampsOn = devices.filter(d => {
    const name = getDeviceName(d)
    const r = statusMap[name] ?? statusMap[name.toLowerCase()]
    const v = r?.isLampOn ?? r?.lamp ?? r?.Lamp
    return v === true || v === 'true' || v === 1 || v === '1'
  }).length
  const fansOn = devices.filter(d => {
    const name = getDeviceName(d)
    const r = statusMap[name] ?? statusMap[name.toLowerCase()]
    const v = r?.fanOnOrOff ?? r?.fanOnOff ?? r?.fan ?? r?.Fan ?? r?.fanSpeed ?? r?.FanSpeed
    if (v === undefined || v === null) return false
    if (typeof v === 'boolean') return v
    if (typeof v === 'number') return v > 0
    return parseFloat(v) > 0
  }).length
  const offlineCount = devices.filter(d => {
    const name = getDeviceName(d)
    const r = statusMap[name] ?? statusMap[name.toLowerCase()]
    const msgs = r?.messagesLast24h ?? r?.MessagesLast24h ?? r?.messages_last_24h ?? null
    if (msgs === null || msgs === undefined) return true
    const n = typeof msgs === 'number' ? msgs : parseInt(msgs, 10)
    return !(n > 0)
  }).length

  // Helper: is a device offline?
  const isDeviceOffline = (d) => {
    const name = getDeviceName(d)
    const r = statusMap[name] ?? statusMap[name.toLowerCase()]
    const msgs = r?.messagesLast24h ?? r?.MessagesLast24h ?? r?.messages_last_24h ?? null
    if (msgs === null || msgs === undefined) return true
    const n = typeof msgs === 'number' ? msgs : parseInt(msgs, 10)
    return !(n > 0)
  }

  // Filtered device list (hide offline when toggle is on)
  const filteredDevices = hideOffline ? devices.filter(d => !isDeviceOffline(d)) : devices

  const connectionOk = !error && lastUpdated !== null

  const formatTime = d =>
    d
      ? d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
      : '—'

  const handleToggleTheme = () => {
    setTheme(prev => (prev === 'dark' ? 'light' : 'dark'))
  }

  // Update status for a specific device after a command
  const handleStatusUpdate = useCallback((deviceName, newRecord) => {
    setStatusMap(prev => ({
      ...prev,
      [deviceName]: newRecord,
      [deviceName.toLowerCase()]: newRecord,
    }))
  }, [])

  // Show login page when not authenticated (skip during redirect processing)
  if (!isAuthenticated && inProgress === InteractionStatus.None) {
    return <LoginPage />
  }

  // Show nothing while MSAL processes a redirect
  if (!isAuthenticated) {
    return null
  }

  const activeAccount = instance.getActiveAccount()

  return (
    <div className="app-wrapper">
      <Header
        connectionOk={connectionOk}
        loading={loading}
        onRefresh={loadData}
        theme={theme}
        onToggleTheme={handleToggleTheme}
        userName={activeAccount?.name}
        onSignOut={() => instance.logoutRedirect()}
        currentView={currentView}
        onNavigate={(view) => { setCurrentView(view); setSelectedDevice(null) }}
      />

      <main className="main-content">
        {currentView === 'architecture' ? (
          <ArchitectureDiagram onBack={() => setCurrentView('dashboard')} />
        ) : selectedDevice ? (
          <DeviceDetailPage
            device={selectedDevice}
            statusRecord={
              (() => {
                const name = getDeviceName(selectedDevice)
                return statusMap[name] ?? statusMap[name.toLowerCase()] ?? null
              })()
            }
            onBack={() => setSelectedDevice(null)}
            onToast={addToast}
            onStatusUpdate={handleStatusUpdate}
          />
        ) : (
          <>
            {/* Section header */}
            <div className="section-header">
              <div className="section-title-group">
                <span className="section-label">// Live Operations</span>
                <h1 className="section-title">Device Control</h1>
              </div>
              <div className="section-header-right">
                <button
                  type="button"
                  className={`filter-offline-btn${hideOffline ? ' active' : ''}`}
                  onClick={() => { setHideOffline(h => !h); setCurrentPage(1) }}
                  title={hideOffline ? 'Show all devices' : 'Hide offline devices'}
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    {hideOffline ? (
                      <>
                        <path d="M1 1l22 22" />
                        <path d="M16.72 11.06A10.94 10.94 0 0 1 19 12.55" />
                        <path d="M5 12.55a10.94 10.94 0 0 1 5.17-2.39" />
                        <path d="M10.71 5.05A16 16 0 0 1 22.56 9" />
                        <path d="M1.42 9a15.91 15.91 0 0 1 4.7-2.88" />
                        <path d="M8.53 16.11a6 6 0 0 1 6.95 0" />
                        <line x1="12" y1="20" x2="12.01" y2="20" />
                      </>
                    ) : (
                      <>
                        <path d="M5 12.55a11 11 0 0 1 14 0" />
                        <path d="M1.42 9a16 16 0 0 1 21.16 0" />
                        <path d="M8.53 16.11a6 6 0 0 1 6.95 0" />
                        <line x1="12" y1="20" x2="12.01" y2="20" />
                      </>
                    )}
                  </svg>
                  {hideOffline ? 'Offline hidden' : 'Hide offline'}
                </button>
                <ViewToggle view={dashboardView} onToggle={setDashboardView} />
                <span className="last-updated">
                  Last sync: {formatTime(lastUpdated)}
                </span>
              </div>
            </div>

            {/* Stats bar */}
            {!error && totalDevices > 0 && (
              <div className="stats-bar">
                <div className="stat-item">
                  <span className="stat-label">Total Devices</span>
                  <span className="stat-value cyan">{totalDevices}</span>
                </div>
                <div className="stat-divider" />
                <div className="stat-item">
                  <span className="stat-label">Hubs</span>
                  <span className="stat-value cyan">{hubs}</span>
                </div>
                <div className="stat-divider" />
                <div className="stat-item">
                  <span className="stat-label">Lamps On</span>
                  <span className="stat-value green">{lampsOn}</span>
                </div>
                <div className="stat-divider" />
                <div className="stat-item">
                  <span className="stat-label">Fans Active</span>
                  <span className="stat-value amber">{fansOn}</span>
                </div>
                <div className="stat-divider" />
                <div className="stat-item">
                  <span className="stat-label">Lamps Off</span>
                  <span className="stat-value red">{totalDevices - lampsOn}</span>
                </div>
                <div className="stat-divider" />
                <div className="stat-item">
                  <span className="stat-label">Offline</span>
                  <span className="stat-value" style={{ color: '#8d6e63' }}>{offlineCount}</span>
                </div>
              </div>
            )}

            {/* Loading */}
            {loading && devices.length === 0 && (
              <div className="state-panel">
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--cyan)" strokeWidth="1.5">
                  <circle cx="12" cy="12" r="10" />
                  <path d="M12 6v6l4 2" />
                </svg>
                <h3>Connecting</h3>
                <p>Establishing connection to IoT Operations backend...</p>
                <div className="spinner" style={{ width: 28, height: 28, borderWidth: 3, color: 'var(--cyan)' }} />
              </div>
            )}

            {/* Error */}
            {error && (
              <div className="state-panel">
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--red)" strokeWidth="1.5">
                  <circle cx="12" cy="12" r="10" />
                  <line x1="12" y1="8" x2="12" y2="12" />
                  <line x1="12" y1="16" x2="12.01" y2="16" />
                </svg>
                <h3>Connection Error</h3>
                <p>{error}</p>
                <button className="retry-btn" onClick={loadData}>
                  Retry
                </button>
              </div>
            )}

            {/* Empty */}
            {!loading && !error && devices.length === 0 && (
              <div className="state-panel">
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--cyan)" strokeWidth="1.5">
                  <rect x="3" y="3" width="18" height="18" rx="2" />
                  <path d="M9 9h6M9 12h6M9 15h4" />
                </svg>
                <h3>No Devices Found</h3>
                <p>No devices were returned by the backend. Check your Eventhouse configuration.</p>
              </div>
            )}

            {/* Device Grid or Map */}
            {!error && devices.length > 0 && (
              dashboardView === 'map' ? (
                <DeviceMapView
                  devices={filteredDevices}
                  statusMap={statusMap}
                  onSelectDevice={setSelectedDevice}
                  theme={theme}
                />
              ) : (
                <DeviceGrid
                  devicesByHub={filteredDevices}
                  statusMap={statusMap}
                  onToast={addToast}
                  onStatusUpdate={handleStatusUpdate}
                  onSelectDevice={setSelectedDevice}
                  currentPage={currentPage}
                  onPageChange={setCurrentPage}
                />
              )
            )}
          </>
        )}
      </main>

      <ToastContainer toasts={toasts} />
    </div>
  )
}
