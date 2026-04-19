import { useState } from 'react'
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

export function DeviceCard({ device, statusRecord, onToast, onStatusUpdate, onCommandComplete, embedded }) {
  const [lampBusy, setLampBusy] = useState(null)
  const [fanBusy, setFanBusy] = useState(null)
  const [blinkBusy, setBlinkBusy] = useState(false)

  const deviceName = getDeviceName(device)
  const hubName = device.hubName ?? device.HubName ?? device.hub ?? device.Hub ?? null

  const lampOn = getLampState(statusRecord)
  const fanOn = getFanState(statusRecord)
  const fanRaw = getFanRaw(statusRecord)
  const currentBlinkPattern = getBlinkPattern(statusRecord)
  const temperature = getTemperature(statusRecord)

  // Determine if device has recent data
  const hasStatus = !!statusRecord
  const isOnline = hasStatus

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
            <div className="device-name">{deviceName}</div>
          </div>
          <div className="card-header-right">
            {temperature !== null && (
              <div className="device-temp">
                <span className="temp-icon" aria-hidden="true">🌡</span>
                <span className="temp-value">{temperature.toFixed(1)}°F</span>
              </div>
            )}
          <div className={`device-online-indicator ${isOnline ? 'online' : 'offline'}`}>
            <span className="led" />
            {isOnline ? 'Online' : 'No Data'}
          </div>
          </div>
        </div>
      )}

      {/* ── Controls ── */}
      <div className="card-controls">
        {/* Lamp controls */}
        <div className="control-row">
          <div className="control-row-label">Lamp Control</div>
          <div className={`control-buttons${lampOn !== null ? ' has-active' : ''}`}>
            <button
              className={`ctrl-btn on-btn${lampOn === true ? ' active' : ''}`}
              disabled={!!lampBusy}
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
            <button
              className={`ctrl-btn off-btn${lampOn === false ? ' active' : ''}`}
              disabled={!!lampBusy}
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
          </div>
        </div>

        {/* Fan controls */}
        <div className="control-row">
          <div className="control-row-label">Fan Control</div>
          <div className={`control-buttons${fanOn !== null ? ' has-active' : ''}`}>
            <button
              className={`ctrl-btn on-btn${fanOn === true ? ' active' : ''}`}
              disabled={!!fanBusy}
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
            <button
              className={`ctrl-btn off-btn${fanOn === false ? ' active' : ''}`}
              disabled={!!fanBusy}
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
                disabled={blinkBusy}
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
    </div>
  )
}
