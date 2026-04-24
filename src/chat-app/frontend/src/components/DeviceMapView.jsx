import { useEffect, useMemo, useRef } from 'react'
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { getLatitude, getLongitude, getHub, getCityForHub } from '../siteLocations.js'

// ── Helpers ──────────────────────────────────────────────────────

function getDeviceName(device) {
  if (!device) return 'Unknown'
  return device.iotInstanceName ?? device.deviceName ?? device.DeviceName
    ?? device.device_name ?? device.Device ?? device.device
    ?? device.name ?? device.Name ?? 'Unknown'
}

function getLampState(record) {
  const val = record?.isLampOn ?? record?.lamp ?? record?.Lamp ?? null
  if (val === null) return null
  if (typeof val === 'boolean') return val
  return String(val).toLowerCase() === 'true' || val === 1 || val === '1'
}

function getFanState(record) {
  const val = record?.fanOnOrOff ?? record?.fanOnOff ?? record?.fan ?? record?.Fan ?? null
  if (val === null) return null
  if (typeof val === 'boolean') return val
  if (typeof val === 'number') return val > 0
  return parseFloat(val) > 0 || String(val).toLowerCase() === 'true'
}

function getTemperature(record) {
  const val = record?.temperatureF ?? record?.temperature ?? record?.Temperature ?? null
  if (val === null) return null
  const n = typeof val === 'number' ? val : parseFloat(val)
  return Number.isFinite(n) ? n : null
}

function getMessagesLast24h(record) {
  if (!record) return 0
  const val = record.messagesLast24h ?? record.MessagesLast24h ?? record.messages_last_24h ?? null
  if (val === null || val === undefined) return 0
  if (typeof val === 'number') return val
  if (typeof val === 'string') {
    const parsed = parseInt(val, 10)
    return isNaN(parsed) ? 0 : parsed
  }
  return 0
}

// ── Custom marker icons ──────────────────────────────────────────

function buildSvgIcon(color, glowColor) {
  const svg = `
    <svg xmlns="http://www.w3.org/2000/svg" width="36" height="48" viewBox="0 0 36 48">
      <defs>
        <filter id="g" x="-50%" y="-50%" width="200%" height="200%">
          <feDropShadow dx="0" dy="0" stdDeviation="3" flood-color="${glowColor}" flood-opacity="0.7"/>
        </filter>
      </defs>
      <path d="M18 0C8.06 0 0 8.06 0 18c0 13.5 18 30 18 30s18-16.5 18-30C36 8.06 27.94 0 18 0z"
            fill="${color}" filter="url(#g)" opacity="0.92"/>
      <circle cx="18" cy="17" r="7" fill="rgba(255,255,255,0.25)" stroke="rgba(255,255,255,0.6)" stroke-width="1.5"/>
    </svg>`
  return L.divIcon({
    html: svg,
    iconSize: [36, 48],
    iconAnchor: [18, 48],
    popupAnchor: [0, -44],
    className: 'map-marker-icon',
  })
}

const ICON_ONLINE  = buildSvgIcon('#00e676', '#00e676')
const ICON_WARN    = buildSvgIcon('#ffab00', '#ffab00')
const ICON_COLD    = buildSvgIcon('#00b8cc', '#00e5ff')
const ICON_HOT     = buildSvgIcon('#ff1744', '#ff1744')
const ICON_OFFLINE = buildSvgIcon('#8d6e63', '#8d6e63')

function pickIcon(device, statusRecord) {
  const isOnline = statusRecord && getMessagesLast24h(statusRecord) > 0
  if (!isOnline) return ICON_OFFLINE
  const temp = getTemperature(statusRecord ?? device)
  if (temp !== null) {
    if (temp > 107) return ICON_HOT
    if (temp > 92) return ICON_WARN
  }
  return ICON_ONLINE
}

// ── Auto-fit bounds ──────────────────────────────────────────────

function FitBounds({ positions }) {
  const map = useMap()
  const prev = useRef(null)

  useEffect(() => {
    if (!positions.length) return
    const key = positions.map(p => `${p[0]},${p[1]}`).join('|')
    if (key === prev.current) return
    prev.current = key
    const bounds = L.latLngBounds(positions)
    map.fitBounds(bounds, { padding: [50, 50], maxZoom: 6 })
  }, [positions, map])

  return null
}

// ── Tile URLs ────────────────────────────────────────────────────

const TILE_DARK  = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
const TILE_LIGHT = 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png'

export function DeviceMapView({ devices, statusMap, onSelectDevice, theme }) {
  const isDark = theme === 'dark'
  // Group devices by hub, using real lat/lng from data
  const sites = useMemo(() => {
    const hubMap = {}
    for (const device of devices) {
      const hub = getHub(device)
      const lat = getLatitude(device)
      const lng = getLongitude(device)
      if (lat === null || lng === null) continue

      const key = hub ?? `${lat},${lng}`
      if (!hubMap[key]) {
        hubMap[key] = { hub, lat, lng, city: getCityForHub(hub), devices: [] }
      }
      hubMap[key].devices.push(device)
    }
    return Object.values(hubMap)
  }, [devices])

  const positions = useMemo(
    () => sites.map(s => [s.lat, s.lng]),
    [sites],
  )

  // Fallback centre if no positions
  const centre = positions.length
    ? [positions[0][0], positions[0][1]]
    : [39.83, -98.58]

  return (
    <div className="device-map-container">
      <MapContainer
        key={theme}
        center={centre}
        zoom={4}
        className="device-map"
        scrollWheelZoom
        zoomControl
      >
        <TileLayer
          attribution='&copy; <a href="https://carto.com/">CARTO</a>'
          url={isDark ? TILE_DARK : TILE_LIGHT}
        />
        <FitBounds positions={positions} />

        {sites.map(site => {
          const deviceCount = site.devices.length
          const firstDevice = site.devices[0]
          const firstStatus = (() => {
            const name = getDeviceName(firstDevice)
            return statusMap[name] ?? statusMap[name?.toLowerCase()] ?? firstDevice
          })()

          return (
            <Marker
              key={`${site.lat}-${site.lng}`}
              position={[site.lat, site.lng]}
              icon={pickIcon(firstDevice, firstStatus)}
            >
              <Popup className="map-popup">
                <div className="map-popup-inner">
                  <div className="map-popup-header">
                    <span className="map-popup-hub">{site.hub ?? '—'}</span>
                    <span className="map-popup-city">{site.city}</span>
                  </div>
                  <div className="map-popup-count">
                    {deviceCount} device{deviceCount !== 1 ? 's' : ''}
                  </div>
                  <div className="map-popup-devices">
                    {site.devices.map(device => {
                      const name = getDeviceName(device)
                      const status = statusMap[name] ?? statusMap[name?.toLowerCase()] ?? device
                      const lamp = getLampState(status)
                      const fan = getFanState(status)
                      const temp = getTemperature(status)
                      return (
                        <div
                          key={name}
                          className="map-popup-device-card"
                          role="button"
                          tabIndex={0}
                          onClick={() => onSelectDevice?.(device)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter' || e.key === ' ') {
                              e.preventDefault()
                              onSelectDevice?.(device)
                            }
                          }}
                        >
                          <div className="popup-card-name">{name}</div>
                          <div className="popup-card-stats">
                            <div className="popup-stat">
                              <span className="popup-stat-icon">🌡</span>
                              <span className="popup-stat-label">Temp</span>
                              <span className={`popup-stat-value ${temp !== null ? (temp > 107 ? 'hot' : temp > 92 ? 'warn' : 'cool') : ''}`}>
                                {temp !== null ? `${temp.toFixed(1)}°F` : '—'}
                              </span>
                            </div>
                            <div className="popup-stat">
                              <span className={`popup-stat-led ${lamp ? 'on' : 'off'}`}>●</span>
                              <span className="popup-stat-label">Lamp</span>
                              <span className={`popup-stat-value ${lamp ? 'on' : 'off'}`}>
                                {lamp === null ? '—' : lamp ? 'On' : 'Off'}
                              </span>
                            </div>
                            <div className="popup-stat">
                              <span className={`popup-stat-fan ${fan ? 'on' : 'off'}`}>⟳</span>
                              <span className="popup-stat-label">Fan</span>
                              <span className={`popup-stat-value ${fan ? 'on' : 'off'}`}>
                                {fan === null ? '—' : fan ? 'On' : 'Off'}
                              </span>
                            </div>
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </div>
              </Popup>
            </Marker>
          )
        })}
      </MapContainer>
    </div>
  )
}
