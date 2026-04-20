import { useEffect, useMemo, useState } from 'react'
import { DeviceCard } from './DeviceCard.jsx'
import { fetchDeviceTelemetry } from '../api.js'

const OVERLAY_OPTIONS = [
  { key: 'fan', label: 'Fan State', onColor: '#2196f3', offColor: '#b71c1c' },
  { key: 'lamp', label: 'Lamp State', onColor: '#ff9800', offColor: '#7b1fa2' },
]
const WINDOW_OPTIONS = [
  { key: 30, label: '30 min', ms: 30 * 60 * 1000, timespan: '30m' },
  { key: 60, label: '1 hr', ms: 60 * 60 * 1000, timespan: '1h' },
  { key: 360, label: '6 hr', ms: 6 * 60 * 60 * 1000, timespan: '6h' },
  { key: 1440, label: '24 hr', ms: 24 * 60 * 60 * 1000, timespan: '1d' },
]
const TELEMETRY_POLL_INTERVAL = 30_000

function toFiniteNumber(value) {
  if (value === null || value === undefined) return null
  if (typeof value === 'number') return Number.isFinite(value) ? value : null
  if (typeof value === 'boolean') return value ? 1 : 0
  if (typeof value === 'string') {
    const parsed = Number.parseFloat(value)
    return Number.isFinite(parsed) ? parsed : null
  }
  return null
}

function normalizeTelemetryRow(row) {
  const tag = String(row?.tag ?? '').toLowerCase()
  const tsValue = row?.timestamp ?? row?.value_timestamp ?? row?.valueTimestamp ?? null
  const timestampMs = tsValue ? new Date(tsValue).getTime() : null

  const valueLong = toFiniteNumber(row?.value_long ?? row?.valueLong)
  const valueInt = toFiniteNumber(row?.value_int ?? row?.valueInt)
  const valueFloat = toFiniteNumber(row?.value_float ?? row?.valueFloat)
  const valueBoolRaw = row?.value_bool ?? row?.valueBool
  const valueBool =
    typeof valueBoolRaw === 'boolean'
      ? (valueBoolRaw ? 1 : 0)
      : toFiniteNumber(valueBoolRaw)

  const numeric = valueFloat ?? valueInt ?? valueLong ?? valueBool

  const point = {
    ts: Number.isFinite(timestampMs) ? timestampMs : Date.now(),
    temperature: null,
    fan: null,
    lamp: null,
    blink: null,
  }

  if (tag.includes('temp') && numeric !== null) {
    const celsius = numeric / 10.0
    point.temperature = celsius * 9 / 5 + 32
  }
  if (tag.includes('fan')) point.fan = numeric
  if (tag.includes('lamp')) point.lamp = valueBool ?? numeric
  if (tag.includes('blink')) point.blink = numeric

  return point
}

function getMetricLabel(metricKey) {
  if (metricKey === 'temperature') return 'Temperature (F)'
  const overlay = OVERLAY_OPTIONS.find(o => o.key === metricKey)
  return overlay?.label ?? metricKey
}

function buildMetricSeries(history, metricKey, windowMs) {
  const rows = Array.isArray(history) ? history : []
  const cutoff = Date.now() - windowMs
  return rows
    .filter(point => Number.isFinite(point?.[metricKey]) && point.ts >= cutoff)
    .sort((a, b) => a.ts - b.ts)
}

function formatMetricValue(value, metricKey) {
  if (!Number.isFinite(value)) return 'No data'
  if (metricKey === 'temperature') return `${value.toFixed(1)} F`
  if (metricKey === 'lamp') return value >= 1 ? 'ON' : 'OFF'
  if (metricKey === 'blink') return `Pattern ${Math.round(value)}`
  return value.toFixed(2)
}

function getDeviceName(device) {
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

function getTemperature(record) {
  if (!record) return null
  const val = record.temperatureF ?? record.temperature ?? record.Temperature ?? record.temp ?? record.Temp ?? null
  if (val === null || val === undefined) return null
  if (typeof val === 'number') return val
  if (typeof val === 'string') {
    const parsed = parseFloat(val)
    return isNaN(parsed) ? null : parsed
  }
  return null
}

export function DeviceDetailPage({ device, statusRecord, onBack, onToast, onStatusUpdate }) {
  const deviceName = getDeviceName(device)
  const hubName = device.hubName ?? device.HubName ?? device.hub ?? device.Hub ?? null

  const [activeMetric] = useState('temperature')
  const [overlays, setOverlays] = useState([])
  const [windowKey, setWindowKey] = useState(1440)
  const [hoveredPointIndex, setHoveredPointIndex] = useState(null)
  const [telemetryData, setTelemetryData] = useState([])
  const [telemetryLoading, setTelemetryLoading] = useState(true)
  const [telemetryError, setTelemetryError] = useState(null)
  const [telemetryRefreshKey, setTelemetryRefreshKey] = useState(0)
  const [zoomRange, setZoomRange] = useState(null)
  const [brushAnchor, setBrushAnchor] = useState(null)
  const [brushCurrent, setBrushCurrent] = useState(null)

  const activeWindow = WINDOW_OPTIONS.find(w => w.key === windowKey) ?? WINDOW_OPTIONS[3]

  // Fetch telemetry on mount, when window changes, and poll
  useEffect(() => {
    let isCancelled = false

    async function loadTelemetry() {
      try {
        const payload = await fetchDeviceTelemetry(deviceName, activeWindow.timespan)
        if (!isCancelled) {
          const points = (payload?.measurements ?? []).map(normalizeTelemetryRow)
          setTelemetryData(points)
          setTelemetryError(null)
          setTelemetryLoading(false)
        }
      } catch (err) {
        if (!isCancelled) {
          setTelemetryError(err.message)
          setTelemetryLoading(false)
        }
      }
    }

    setTelemetryLoading(true)
    loadTelemetry()
    const intervalId = setInterval(loadTelemetry, TELEMETRY_POLL_INTERVAL)

    return () => {
      isCancelled = true
      clearInterval(intervalId)
    }
  }, [deviceName, activeWindow.timespan, telemetryRefreshKey])

  // Reset hover on metric/window change

  useEffect(() => {
    setHoveredPointIndex(null)
    setZoomRange(null)
  }, [activeMetric, windowKey])

  const graphSeries = useMemo(
    () => buildMetricSeries(telemetryData, activeMetric, activeWindow.ms),
    [telemetryData, activeMetric, activeWindow.ms],
  )

  const visibleSeries = useMemo(() => {
    if (!zoomRange) return graphSeries
    return graphSeries.filter(p => p.ts >= zoomRange.minTs && p.ts <= zoomRange.maxTs)
  }, [graphSeries, zoomRange])

  // Build overlay event series for fan/lamp
  const overlaySeries = useMemo(() => {
    const cutoff = Date.now() - activeWindow.ms
    return overlays.map(key => {
      const config = OVERLAY_OPTIONS.find(o => o.key === key)
      if (!config) return null
      const events = telemetryData
        .filter(p => Number.isFinite(p?.[key]) && p.ts >= cutoff)
        .sort((a, b) => a.ts - b.ts)
        .map(p => ({
          ts: p.ts,
          isOn: key === 'fan' ? p[key] > 0 : p[key] >= 1,
        }))
      return { key, config, events }
    }).filter(Boolean)
  }, [overlays, telemetryData, activeWindow.ms])

  const chartWidth = 1200
  const chartHeight = 420
  const chartPaddingLeft = 64
  const chartPaddingRight = 40
  const chartPaddingTop = 16
  const chartPaddingBottom = 46
  const pointCount = visibleSeries.length

  const metricValues = visibleSeries.map(p => p[activeMetric])
  const rawMinValue = pointCount > 0 ? Math.min(...metricValues) : 0
  const rawMaxValue = pointCount > 0 ? Math.max(...metricValues) : 1
  const hasRange = rawMaxValue - rawMinValue > 0
  const rangeBuffer = hasRange ? (rawMaxValue - rawMinValue) * 0.08 : 0.5
  const paddedMinValue = rawMinValue - rangeBuffer
  const paddedMaxValue = rawMaxValue + rangeBuffer
  const valueSpan = paddedMaxValue - paddedMinValue || 1

  const plotHeight = chartHeight - chartPaddingTop - chartPaddingBottom
  const plotWidth = chartWidth - chartPaddingLeft - chartPaddingRight

  const points = visibleSeries.map((point, index) => {
    const x =
      chartPaddingLeft +
      (pointCount <= 1 ? 0 : (index / (pointCount - 1)) * plotWidth)
    const normalized = (point[activeMetric] - paddedMinValue) / valueSpan
    const y = chartPaddingTop + plotHeight - normalized * plotHeight
    return { x, y, ts: point.ts, value: point[activeMetric] }
  })

  const pathD = points
    .map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x.toFixed(2)} ${p.y.toFixed(2)}`)
    .join(' ')

  // Build color-segmented paths for temperature metric
  // Uses the average value between consecutive points to determine segment color
  const tempColorSegments = useMemo(() => {
    if (activeMetric !== 'temperature' || points.length < 2) return null
    const segments = []
    let currentColor = null
    let currentD = ''
    for (let i = 0; i < points.length - 1; i++) {
      const avgVal = (points[i].value + points[i + 1].value) / 2
      const color = avgVal <= 92 ? '#22b14c' : avgVal <= 107 ? '#e6a800' : '#e60026'
      if (color !== currentColor) {
        if (currentD) segments.push({ color: currentColor, d: currentD })
        currentColor = color
        currentD = `M ${points[i].x.toFixed(2)} ${points[i].y.toFixed(2)} L ${points[i + 1].x.toFixed(2)} ${points[i + 1].y.toFixed(2)}`
      } else {
        currentD += ` L ${points[i + 1].x.toFixed(2)} ${points[i + 1].y.toFixed(2)}`
      }
    }
    if (currentD) segments.push({ color: currentColor, d: currentD })
    return segments
  }, [activeMetric, points])

  const isTemperatureColored = tempColorSegments !== null && tempColorSegments.length > 0

  // Area fill path
  // Y-axis ticks — pick ~5 evenly spaced values
  const yAxisTicks = useMemo(() => {
    if (pointCount < 2) return []
    const tickCount = 5
    const ticks = []
    for (let i = 0; i < tickCount; i++) {
      const ratio = i / (tickCount - 1)
      const value = paddedMinValue + ratio * valueSpan
      const y = chartPaddingTop + plotHeight - ratio * plotHeight
      ticks.push({ y, label: value.toFixed(1) })
    }
    return ticks
  }, [paddedMinValue, valueSpan, plotHeight, pointCount, chartPaddingTop])

  const areaBottom = chartPaddingTop + plotHeight
  const areaD = points.length > 1
    ? pathD + ` L ${points[points.length - 1].x.toFixed(2)} ${areaBottom} L ${points[0].x.toFixed(2)} ${areaBottom} Z`
    : ''

  // X-axis tick labels — pick ~5-6 evenly spaced ticks
  const xAxisTicks = useMemo(() => {
    if (points.length < 2) return []
    const maxTicks = Math.min(6, points.length)
    const step = (points.length - 1) / (maxTicks - 1)
    const ticks = []
    for (let i = 0; i < maxTicks; i++) {
      const idx = Math.round(i * step)
      const p = points[idx]
      if (p) {
        const d = new Date(p.ts)
        const label = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        ticks.push({ x: p.x, label })
      }
    }
    return ticks
  }, [points])

  // Interpolated hover point that tracks cursor position on the line
  const cursorPoint = useMemo(() => {
    if (hoveredPointIndex === null || points.length < 2) return null
    return points[hoveredPointIndex] ?? null
  }, [hoveredPointIndex, points])

  const displayedPoint = cursorPoint ?? (points.length > 0 ? points[points.length - 1] : null)

  const tempValueStyle = (val) => {
    if (activeMetric !== 'temperature' || !Number.isFinite(val)) return undefined
    const color = val <= 92 ? '#22b14c' : val <= 107 ? '#e6a800' : '#e60026'
    return { color }
  }

  const tempBadgeStyle = (val) => {
    if (!Number.isFinite(val)) return {}
    if (val <= 92) return { color: '#22b14c', background: 'rgba(34, 177, 76, 0.12)', borderColor: 'rgba(34, 177, 76, 0.3)' }
    if (val <= 107) return { color: '#e6a800', background: 'rgba(230, 168, 0, 0.12)', borderColor: 'rgba(230, 168, 0, 0.3)' }
    return { color: '#e60026', background: 'rgba(230, 0, 38, 0.12)', borderColor: 'rgba(230, 0, 38, 0.3)' }
  }

  const formatTimestamp = (ts) => {
    if (!ts) return 'No data'
    return new Date(ts).toLocaleString([], {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
  }

  const getPlotRatio = (event) => {
    const rect = event.currentTarget.getBoundingClientRect()
    const screenRatio = (event.clientX - rect.left) / rect.width
    const svgX = screenRatio * chartWidth
    return Math.max(0, Math.min(1, (svgX - chartPaddingLeft) / plotWidth))
  }

  const handleChartMouseDown = (event) => {
    if (points.length < 2) return
    event.preventDefault()
    const ratio = getPlotRatio(event)
    setBrushAnchor(ratio)
    setBrushCurrent(ratio)
  }

  const handleChartMouseMove = (event) => {
    if (points.length === 0) return
    const ratio = getPlotRatio(event)
    if (brushAnchor !== null) {
      setBrushCurrent(ratio)
    } else {
      const nearestIndex = Math.round(ratio * (points.length - 1))
      setHoveredPointIndex(nearestIndex)
    }
  }

  const handleChartMouseUp = () => {
    if (brushAnchor !== null && brushCurrent !== null && points.length >= 2) {
      const r1 = Math.min(brushAnchor, brushCurrent)
      const r2 = Math.max(brushAnchor, brushCurrent)
      if (r2 - r1 > 0.03) {
        const minTs = points[0].ts
        const maxTs = points[points.length - 1].ts
        const tsSpan = maxTs - minTs
        setZoomRange({
          minTs: minTs + r1 * tsSpan,
          maxTs: minTs + r2 * tsSpan,
        })
        setHoveredPointIndex(null)
      }
    }
    setBrushAnchor(null)
    setBrushCurrent(null)
  }

  const handleChartLeave = () => {
    setHoveredPointIndex(null)
    setBrushAnchor(null)
    setBrushCurrent(null)
  }

  return (
    <div className="detail-page">
      {/* Back navigation */}
      <button type="button" className="detail-back-btn" onClick={onBack}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <polyline points="15 18 9 12 15 6" />
        </svg>
        Back to All Devices
      </button>

      {/* Device header */}
      <div className="detail-header">
        <div>
          {hubName && (
            <div className="detail-hub">hub · <span>{hubName}</span></div>
          )}
          <h1 className="detail-device-name">{deviceName}</h1>
        </div>
        <div className="detail-header-badges">
          {statusRecord && getTemperature(statusRecord) !== null && (
            <div className="detail-temp-badge">
              <span aria-hidden="true">🌡</span>
              <span>{getTemperature(statusRecord).toFixed(1)}°F</span>
            </div>
          )}
          <div className={`detail-online-badge ${statusRecord ? 'online' : 'offline'}`}>
            <span className="led" />
            {statusRecord ? 'Online' : 'No Data'}
          </div>
        </div>
      </div>

      {/* Side-by-side: controls panel + telemetry chart */}
      <div className="detail-side-by-side">

      {/* Device controls panel */}
      <section className="detail-controls-section">
        <div className="detail-section-label">Device Controls</div>
        <DeviceCard
          device={device}
          statusRecord={statusRecord}
          onToast={onToast}
          onStatusUpdate={onStatusUpdate}
          onCommandComplete={() => setTelemetryRefreshKey(k => k + 1)}
          embedded
        />
      </section>

      {/* Telemetry */}
      <section className="detail-telemetry-section">
        <div className="telemetry-header">
          <div>
            <div className="telemetry-label">Live Telemetry</div>
            <div className="telemetry-title">
              {deviceName} · Temperature (F)
              {zoomRange && (
                <button type="button" className="zoom-reset-btn" onClick={() => setZoomRange(null)}>
                  ✕ Reset Zoom
                </button>
              )}
            </div>
          </div>
          <div className="telemetry-controls">
            <div className="telemetry-control-group">
              <span className="telemetry-chip active" style={{ cursor: 'default' }}>
                Temperature (F)
              </span>
              {OVERLAY_OPTIONS.map(option => (
                <button
                  key={option.key}
                  type="button"
                  className={`telemetry-chip ${overlays.includes(option.key) ? 'active' : ''}`}
                  onClick={() =>
                    setOverlays(prev =>
                      prev.includes(option.key)
                        ? prev.filter(k => k !== option.key)
                        : [...prev, option.key],
                    )
                  }
                >
                  {option.label}
                </button>
              ))}
            </div>
            <div className="telemetry-control-group">
              {WINDOW_OPTIONS.map(opt => (
                <button
                  key={opt.key}
                  type="button"
                  className={`telemetry-chip ${windowKey === opt.key ? 'active' : ''}`}
                  onClick={() => setWindowKey(opt.key)}
                >
                  {opt.label}
                </button>
              ))}
            </div>
          </div>
        </div>

        <div
          className="telemetry-chart-wrap detail-chart-wrap"
          onMouseDown={handleChartMouseDown}
          onMouseMove={handleChartMouseMove}
          onMouseUp={handleChartMouseUp}
          onMouseLeave={handleChartLeave}
          style={{ cursor: points.length > 1 ? 'crosshair' : undefined, userSelect: 'none' }}
        >
          {telemetryLoading ? (
            <div className="telemetry-empty">
              <span className="spinner" style={{ width: 20, height: 20, borderWidth: 2 }} />
              &nbsp;&nbsp;Loading telemetry data...
            </div>
          ) : telemetryError ? (
            <div className="telemetry-empty" style={{ color: 'var(--red)' }}>
              Failed to load telemetry: {telemetryError}
            </div>
          ) : points.length > 1 ? (
            <svg className="telemetry-chart detail-chart" viewBox={`0 0 ${chartWidth} ${chartHeight}`} role="img" aria-label={`Telemetry chart for ${deviceName}`}>
              <defs>
                <linearGradient id="areaGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="var(--cyan)" stopOpacity="0.18" />
                  <stop offset="100%" stopColor="var(--cyan)" stopOpacity="0" />
                </linearGradient>
              </defs>
              {!isTemperatureColored && areaD && <path d={areaD} fill="url(#areaGrad)" />}
              {isTemperatureColored ? (
                tempColorSegments.map((seg, i) => (
                  <path
                    key={i}
                    d={seg.d}
                    fill="none"
                    stroke={seg.color}
                    strokeWidth="3"
                    strokeLinejoin="round"
                  />
                ))
              ) : (
                <path className="telemetry-path" d={pathD} />
              )}
              {/* Y-axis line */}
              <line
                x1={chartPaddingLeft}
                y1={chartPaddingTop}
                x2={chartPaddingLeft}
                y2={chartPaddingTop + plotHeight}
                stroke="var(--border-mid)"
                strokeWidth="1"
              />
              {/* Y-axis ticks */}
              {yAxisTicks.map((tick, i) => (
                <g key={`y-${i}`}>
                  <line
                    x1={chartPaddingLeft - 6}
                    y1={tick.y}
                    x2={chartPaddingLeft}
                    y2={tick.y}
                    stroke="var(--border-mid)"
                    strokeWidth="1"
                  />
                  <text
                    x={chartPaddingLeft - 10}
                    y={tick.y + 3}
                    textAnchor="end"
                    className="chart-axis-label"
                  >
                    {tick.label}
                  </text>
                </g>
              ))}
              {/* X-axis baseline */}
              <line
                x1={chartPaddingLeft}
                y1={chartPaddingTop + plotHeight}
                x2={chartWidth - chartPaddingRight}
                y2={chartPaddingTop + plotHeight}
                stroke="var(--border-mid)"
                strokeWidth="1"
              />
              {/* X-axis timestamp ticks */}
              {xAxisTicks.map((tick, i) => (
                <g key={i}>
                  <line
                    x1={tick.x}
                    y1={chartPaddingTop + plotHeight}
                    x2={tick.x}
                    y2={chartPaddingTop + plotHeight + 6}
                    stroke="var(--border-mid)"
                    strokeWidth="1"
                  />
                  <text
                    x={tick.x}
                    y={chartPaddingTop + plotHeight + 22}
                    textAnchor="middle"
                    className="chart-axis-label"
                  >
                    {tick.label}
                  </text>
                </g>
              ))}
              {/* Data points (small dots) - skip for temperature colored mode */}
              {!isTemperatureColored && points.map((point, index) => (
                <circle
                  key={`${point.ts}-${index}`}
                  cx={point.x}
                  cy={point.y}
                  r={2}
                  className="telemetry-point"
                />
              ))}
              {/* Overlay event markers for fan/lamp */}
              {overlaySeries.map(overlay => {
                if (!overlay.events.length || points.length < 2) return null
                const minTs = points[0].ts
                const maxTs = points[points.length - 1].ts
                const tsSpan = maxTs - minTs || 1
                // Only render state-change transitions to keep markers sparse
                const transitions = []
                for (let i = 0; i < overlay.events.length; i++) {
                  if (i === 0 || overlay.events[i].isOn !== overlay.events[i - 1].isOn) {
                    transitions.push(overlay.events[i])
                  }
                }
                return transitions.map((evt, i) => {
                  const xRatio = (evt.ts - minTs) / tsSpan
                  const x = chartPaddingLeft + xRatio * plotWidth
                  if (x < chartPaddingLeft || x > chartWidth - chartPaddingRight) return null
                  const markerY = chartPaddingTop + plotHeight - 10
                  const color = evt.isOn ? overlay.config.onColor : overlay.config.offColor
                  return (
                    <g key={`${overlay.key}-${i}`}>
                      <line
                        x1={x}
                        y1={chartPaddingTop}
                        x2={x}
                        y2={chartPaddingTop + plotHeight}
                        stroke={color}
                        strokeWidth="1"
                        strokeDasharray="3 4"
                        opacity="0.35"
                      />
                      <circle cx={x} cy={markerY} r={5} fill={color} opacity="0.9" />
                      <text
                        x={x}
                        y={markerY - 10}
                        textAnchor="middle"
                        fill={color}
                        fontSize="9"
                        fontFamily="var(--font-mono)"
                        fontWeight="700"
                        letterSpacing="0.05em"
                      >
                        {evt.isOn ? 'ON' : 'OFF'}
                      </text>
                    </g>
                  )
                })
              })}
              {/* Brush selection rectangle */}
              {brushAnchor !== null && brushCurrent !== null && (
                <rect
                  x={chartPaddingLeft + Math.min(brushAnchor, brushCurrent) * plotWidth}
                  y={chartPaddingTop}
                  width={Math.abs(brushCurrent - brushAnchor) * plotWidth}
                  height={plotHeight}
                  fill="var(--cyan)"
                  opacity="0.1"
                  stroke="var(--cyan)"
                  strokeWidth="1"
                  strokeDasharray="4 3"
                  pointerEvents="none"
                />
              )}
              {/* Hover crosshair + cursor dot */}
              {cursorPoint && (
                <>
                  <line
                    x1={cursorPoint.x}
                    y1={chartPaddingTop}
                    x2={cursorPoint.x}
                    y2={chartPaddingTop + plotHeight}
                    stroke="var(--cyan)"
                    strokeWidth="1"
                    strokeDasharray="4 3"
                    opacity="0.4"
                  />
                  <circle
                    cx={cursorPoint.x}
                    cy={cursorPoint.y}
                    r={6}
                    fill="var(--bg-panel)"
                    stroke="var(--cyan)"
                    strokeWidth="2"
                    className="telemetry-cursor-dot"
                  />
                  <circle
                    cx={cursorPoint.x}
                    cy={cursorPoint.y}
                    r={3}
                    fill="var(--cyan)"
                    className="telemetry-cursor-dot-inner"
                  />
                </>
              )}
            </svg>
          ) : (
            <div className="telemetry-empty">Collecting telemetry... wait for at least two data points.</div>
          )}
        </div>

        <div className="telemetry-meta detail-meta">
          <span className="detail-meta-item">
            <span className="detail-meta-label">Current</span>
            <span className="detail-meta-value" style={tempValueStyle(displayedPoint?.value)}>{formatMetricValue(displayedPoint?.value, activeMetric)}</span>
          </span>
          <span className="detail-meta-item">
            <span className="detail-meta-label">Min</span>
            <span className="detail-meta-value" style={tempValueStyle(metricValues.length ? Math.min(...metricValues) : null)}>{formatMetricValue(metricValues.length ? Math.min(...metricValues) : null, activeMetric)}</span>
          </span>
          <span className="detail-meta-item">
            <span className="detail-meta-label">Max</span>
            <span className="detail-meta-value" style={tempValueStyle(metricValues.length ? Math.max(...metricValues) : null)}>{formatMetricValue(metricValues.length ? Math.max(...metricValues) : null, activeMetric)}</span>
          </span>
          <span className="detail-meta-item">
            <span className="detail-meta-label">Timestamp</span>
            <span className="detail-meta-value">{formatTimestamp(displayedPoint?.ts)}</span>
          </span>
          <span className="detail-meta-item">
            <span className="detail-meta-label">Data Points</span>
            <span className="detail-meta-value">{pointCount}</span>
          </span>
        </div>

        {overlays.length > 0 && (
          <div className="overlay-legend">
            {OVERLAY_OPTIONS.filter(o => overlays.includes(o.key)).map(o => (
              <div key={o.key} className="overlay-legend-item">
                <span className="overlay-legend-dot" style={{ background: o.onColor }} />
                <span className="overlay-legend-label">{o.label} ON</span>
                <span className="overlay-legend-dot" style={{ background: o.offColor }} />
                <span className="overlay-legend-label">{o.label} OFF</span>
              </div>
            ))}
          </div>
        )}
      </section>

      </div>{/* end detail-side-by-side */}
    </div>
  )
}
