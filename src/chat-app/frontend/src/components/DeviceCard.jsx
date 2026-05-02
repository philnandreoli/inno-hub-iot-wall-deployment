import { useState, useEffect } from 'react'
import {
  sendLampOn,
  sendLampOff,
  sendFanOn,
  sendFanOff,
  sendBlinkPattern,
  fetchDeviceStatus,
} from '../api.js'

const BLINK_PATTERNS = [0, 1, 2, 3, 4, 5, 6]

function getLampState(record) {
  if (!record) return null
  // Try actual API field names first, then fallbacks
  const val =
    record.isLampOn ?? record.lamp ?? record.Lamp ?? record.lampState ?? record.LampState ?? null
  if (val === null || val === undefined) return null
  if (typeof val === 'boolean') return val
  if (typeof val === 'number') return val !== 0
  if (typeof val === 'string') return val.toLowerCase() === 'true' || val === '1' || val.toLowerCase() === 'on'
  return null
}

function getFanState(record) {
  if (!record) return null
  // Try actual API field names first, then fallbacks
  const val =
    record.fanOnOrOff ?? record.fanOnOff ?? record.fan ?? record.Fan ?? record.fanSpeed ?? record.FanSpeed ?? null
  if (val === null || val === undefined) return null
  if (typeof val === 'boolean') return val
  if (typeof val === 'number') return val > 0
  if (typeof val === 'string') return parseFloat(val) > 0 || val.toLowerCase() === 'true' || val.toLowerCase() === 'on'
  return null
}

function getFanRaw(record) {
  if (!record) return null
  return record.fanOnOrOff ?? record.fanOnOff ?? record.fan ?? record.Fan ?? record.fanSpeed ?? record.FanSpeed ?? null
}

function getBlinkPattern(record) {
  if (!record) return null
  const val = record.blinkPattern ?? record.BlinkPattern ?? record.blink_pattern ?? null
  if (val === null || val === undefined) return null
  if (typeof val === 'number') return val
  if (typeof val === 'string') return parseInt(val, 10)
  return null
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

function getLuezeMessagesLast24h(record) {
  if (!record) return 0
  const val = record.luezeMessagesLast24h ?? record.LuezeMessagesLast24h ?? record.lueze_messages_last_24h ?? null
  if (val === null || val === undefined) return 0
  if (typeof val === 'number') return val
  if (typeof val === 'string') {
    const parsed = parseInt(val, 10)
    return isNaN(parsed) ? 0 : parsed
  }
  return 0
}

// Returns 'online' | 'partial' | 'offline'
function getConnectionStatus(record) {
  if (!record) return 'offline'
  const beckhoff = getMessagesLast24h(record) > 0
  const lueze = getLuezeMessagesLast24h(record) > 0
  if (beckhoff && lueze) return 'online'
  if (beckhoff || lueze) return 'partial'
  return 'offline'
}

function getLuezeBarcode(record) {
  if (!record) return null
  return record.luezelastReadBarcode ?? record.luezeLastReadBarcode ?? record.LuezeLastReadBarcode ?? null
}

function getLuezeTimestamp(record) {
  if (!record) return null
  return record.luezeBarcodeIngestionTime ?? record.LuezeBarcodeIngestionTime ?? null
}

function getLuezeRecordCount(record) {
  if (!record) return 0
  return getLuezeMessagesLast24h(record)
}

/**
 * Derive the Azure Arc status for a device given its arc-status API response
 * and message counts.
 *
 * Returns: 'connected' | 'offline' | 'partial' | 'not-implemented'
 */
function deriveAzureStatus(arcData, messagesLast24h, luezeMessagesLast24h) {
  if (!arcData) return 'not-implemented'

  const hostStatus = arcData.host?.status?.toLowerCase() ?? ''
  const vmStatus = arcData.vm?.status?.toLowerCase() ?? ''
  const k8sStatus = arcData.k8sCluster?.status?.toLowerCase() ?? ''

  const allConnected = hostStatus === 'connected' && vmStatus === 'connected' && k8sStatus === 'connected'
  const allDisconnected = hostStatus === 'disconnected' && vmStatus === 'disconnected' && k8sStatus === 'disconnected'

  if (allConnected && messagesLast24h > 0 && luezeMessagesLast24h > 0) return 'connected'
  if (allDisconnected) return 'offline'
  return 'partial'
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
  return name || ''
}

export function DeviceCard({ device, statusRecord, arcStatusData, onToast, onStatusUpdate, onCommandComplete, onSelectDevice, embedded }) {
  const [lampBusy, setLampBusy] = useState(null)
  const [fanBusy, setFanBusy] = useState(null)
  const [blinkBusy, setBlinkBusy] = useState(false)
  const [azureStatus, setAzureStatus] = useState('not-implemented')

  const deviceName = getDeviceName(device)
  const hubName = device.hubName ?? device.HubName ?? device.hub ?? device.Hub ?? null

  const lampOn = getLampState(statusRecord)
  const fanOn = getFanState(statusRecord)
  const fanRaw = getFanRaw(statusRecord)
  const currentBlinkPattern = getBlinkPattern(statusRecord)
  const temperature = getTemperature(statusRecord)

  // Determine connection status: online (both), partial (one), offline (neither)
  const connectionStatus = getConnectionStatus(statusRecord)
  const isOnline = connectionStatus !== 'offline'

  // Leuze barcode reader data
  const luezeBarcode = getLuezeBarcode(statusRecord)
  const luezeTimestamp = getLuezeTimestamp(statusRecord)
  const luezeRecordCount = getLuezeRecordCount(statusRecord)

  // Derive azure status from batch arc data passed by parent
  useEffect(() => {
    if (!deviceName || deviceName === 'Unknown' || !deviceName.includes('-')) {
      setAzureStatus('not-implemented')
      return
    }

    if (!arcStatusData) {
      setAzureStatus('not-implemented')
      return
    }

    if (arcStatusData.error) {
      setAzureStatus('not-implemented')
    } else {
      const msgs = getMessagesLast24h(statusRecord)
      const luezeMsgs = getLuezeMessagesLast24h(statusRecord)
      setAzureStatus(deriveAzureStatus(arcStatusData, msgs, luezeMsgs))
    }
  }, [deviceName, statusRecord, arcStatusData])

  function tempBadgeStyle(val) {
    if (!Number.isFinite(val)) return {}
    if (val <= 92) return { color: '#22b14c', background: 'rgba(34, 177, 76, 0.12)', borderColor: 'rgba(34, 177, 76, 0.3)' }
    if (val <= 107) return { color: '#e6a800', background: 'rgba(230, 168, 0, 0.12)', borderColor: 'rgba(230, 168, 0, 0.3)' }
    return { color: '#e60026', background: 'rgba(230, 0, 38, 0.12)', borderColor: 'rgba(230, 0, 38, 0.3)' }
  }

  async function handleCmd(fn, setbusy, busyLabel, successMsg, errorMsg, shouldRefresh = false) {
    setbusy(busyLabel)
    try {
      await fn()
      onToast(successMsg, 'success')

      // Keep spinner running until the status refresh returns
      if (shouldRefresh && onStatusUpdate) {
        try {
          await new Promise(resolve => setTimeout(resolve, 3000))
          const newStatus = await fetchDeviceStatus(deviceName)
          onStatusUpdate(deviceName, newStatus.record)
        } catch (e) {
          console.error('Failed to refresh device status:', e)
        }
      }

      // Trigger telemetry graph refresh after command completes
      if (onCommandComplete) onCommandComplete()
    } catch (e) {
      onToast(`${errorMsg}: ${e.message}`, 'error')
    } finally {
      setbusy(typeof busyLabel === 'boolean' ? false : null)
    }
  }

  return (
    <div className={`device-card${embedded ? ' device-card--embedded' : ''}`}>
      {/* ── Card Header (hidden in embedded/detail mode) ── */}
      {!embedded && (
        <div className="card-header">
          <div className="card-header-left">
            {hubName && (
              <div className="device-hub">
                hub · <span>{hubName}</span>
              </div>
            )}
            <div
              className="device-name"
              role="button"
              tabIndex={0}
              onClick={() => onSelectDevice && onSelectDevice(device)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                  e.preventDefault()
                  onSelectDevice && onSelectDevice(device)
                }
              }}
              aria-label={`View details for ${deviceName}`}
              style={{ cursor: onSelectDevice ? 'pointer' : 'default' }}
            >{deviceName}</div>
          </div>
          <div className="card-header-right">
            {temperature !== null && (
              <div className="device-temp" style={tempBadgeStyle(temperature)}>
                <span className="temp-icon" aria-hidden="true">🌡</span>
                <span className="temp-value">{temperature.toFixed(1)}°F</span>
              </div>
            )}
          <div className={`azure-status-badge azure-status--${azureStatus}`}>
            <span className="azure-status-icon" aria-hidden="true">☁</span>
            {azureStatus === 'connected' ? 'Connected' : azureStatus === 'offline' ? 'Offline' : azureStatus === 'partial' ? 'Degraded' : 'Not Implemented'}
          </div>
          </div>
        </div>
      )}

      {/* ── Beckhoff Controller ── */}
      <div className="controller-section-label beckhoff">
        <span className="section-icon" aria-hidden="true">⚙</span>
        <span className="section-text">Beckhoff Controller</span>
      </div>
      <div className={`card-controls${!isOnline ? ' controls-disabled' : ''}`}>
        {/* Lamp controls */}
        <div className="control-row">
          <div className="control-row-label">Lamp Control</div>
          <div className={`control-buttons${lampOn !== null ? ' has-active' : ''}`}>
            <button
              className={`ctrl-btn off-btn${lampOn === false ? ' active' : ''}`}
              disabled={!isOnline || !!lampBusy}
              onClick={() =>
                handleCmd(
                  () => sendLampOff(deviceName),
                  setLampBusy,
                  'off',
                  `Lamp OFF → ${deviceName}`,
                  'Lamp OFF failed',
                  true,
                )
              }
            >
              {lampBusy === 'off' ? <span className="spinner" /> : null}
              ○ OFF
            </button>
            <button
              className={`ctrl-btn on-btn${lampOn === true ? ' active' : ''}`}
              disabled={!isOnline || !!lampBusy}
              onClick={() =>
                handleCmd(
                  () => sendLampOn(deviceName),
                  setLampBusy,
                  'on',
                  `Lamp ON → ${deviceName}`,
                  'Lamp ON failed',
                  true,
                )
              }
            >
              {lampBusy === 'on' ? <span className="spinner" /> : null}
              ◉ ON
            </button>
          </div>
        </div>

        {/* Fan controls */}
        <div className="control-row">
          <div className="control-row-label">Fan Control</div>
          <div className={`control-buttons${fanOn !== null ? ' has-active' : ''}`}>
            <button
              className={`ctrl-btn off-btn${fanOn === false ? ' active' : ''}`}
              disabled={!isOnline || !!fanBusy}
              onClick={() =>
                handleCmd(
                  () => sendFanOff(deviceName),
                  setFanBusy,
                  'off',
                  `Fan OFF → ${deviceName}`,
                  'Fan OFF failed',
                  true,
                )
              }
            >
              {fanBusy === 'off' ? <span className="spinner" /> : null}
              ○ OFF
            </button>
            <button
              className={`ctrl-btn on-btn${fanOn === true ? ' active' : ''}`}
              disabled={!isOnline || !!fanBusy}
              onClick={() =>
                handleCmd(
                  () => sendFanOn(deviceName),
                  setFanBusy,
                  'on',
                  `Fan ON → ${deviceName}`,
                  'Fan ON failed',
                  true,
                )
              }
            >
              {fanBusy === 'on' ? <span className="spinner" /> : null}
              ◎ ON
            </button>
          </div>
        </div>

        {/* Blink patterns */}
        <div className="control-row blink-section">
          <div className="control-row-label">Blink Pattern</div>
          <div className="blink-patterns">
            {BLINK_PATTERNS.map(n => (
              <button
                key={n}
                className={`blink-btn${currentBlinkPattern === n ? ' active' : ''}`}
                disabled={!isOnline || blinkBusy}
                onClick={() =>
                  handleCmd(
                    () => sendBlinkPattern(deviceName, n),
                    setBlinkBusy,
                    true,
                    `Blink #${n} → ${deviceName}`,
                    `Blink #${n} failed`,
                    true,
                  )
                }
              >
                {n}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* ── Leuze Barcode Reader ── */}
      <hr className="card-section-divider" />
      <div className="controller-section-label leuze">
        <span className="section-icon" aria-hidden="true">📡</span>
        <span className="section-text">Leuze Barcode Reader</span>
      </div>
      <div className="leuze-data">
        <div className="leuze-stat-row">
          <div className="leuze-stat-label">Last Barcode Read</div>
          <div className={`leuze-barcode-value${!luezeBarcode ? ' leuze-no-data' : ''}`}>
            <div className={`barcode-icon${!luezeBarcode ? ' barcode-icon--dim' : ''}`} aria-hidden="true">
              <span className="bar" /><span className="bar" /><span className="bar" /><span className="bar" /><span className="bar" /><span className="bar" /><span className="bar" />
            </div>
            {luezeBarcode || 'No data yet'}
          </div>
        </div>
        <div className="leuze-stat-row">
          <div className="leuze-stat-label">Time Read</div>
          <div className={`leuze-time-value${!luezeTimestamp ? ' leuze-no-data' : ''}`}>
            {luezeTimestamp || '—'}
          </div>
        </div>
        <div className="leuze-stat-row">
          <div className="leuze-stat-label">Total Records Processed</div>
          <div className="leuze-count-row">
            <div className="leuze-count-value">{luezeRecordCount.toLocaleString()}</div>
          </div>
        </div>
      </div>
    </div>
  )
}
