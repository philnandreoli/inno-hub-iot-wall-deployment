/**
 * Shared field-resolution helpers for device data.
 *
 * The backend API returns device records with inconsistent field names
 * (e.g. `iotInstanceName` vs `deviceName` vs `DeviceName`). These helpers
 * normalise the access so every component reads from a single source of truth.
 */

/**
 * Resolve the canonical display name for a device object.
 * Returns 'Unknown' when no name can be found.
 */
export function getDeviceName(device) {
  if (!device) return 'Unknown'
  let name =
    device.iotInstanceName ??
    device.deviceName ??
    device.DeviceName ??
    device.device_name ??
    device.Device ??
    device.device ??
    device.name ??
    device.Name ??
    null
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

/**
 * Resolve the lamp on/off state from a status record.
 * Returns true (on), false (off), or null (unknown).
 */
export function getLampState(record) {
  if (!record) return null
  const val =
    record.isLampOn ??
    record.lamp ??
    record.Lamp ??
    record.lampState ??
    record.LampState ??
    null
  if (val === null || val === undefined) return null
  if (typeof val === 'boolean') return val
  if (typeof val === 'number') return val !== 0
  if (typeof val === 'string') return val.toLowerCase() === 'true' || val === '1' || val.toLowerCase() === 'on'
  return null
}

/**
 * Resolve the fan on/off state from a status record.
 * Returns true (on), false (off), or null (unknown).
 */
export function getFanState(record) {
  if (!record) return null
  const val =
    record.fanOnOrOff ??
    record.fanOnOff ??
    record.fan ??
    record.Fan ??
    record.fanSpeed ??
    record.FanSpeed ??
    null
  if (val === null || val === undefined) return null
  if (typeof val === 'boolean') return val
  if (typeof val === 'number') return val > 0
  if (typeof val === 'string') return parseFloat(val) > 0 || val.toLowerCase() === 'true' || val.toLowerCase() === 'on'
  return null
}

/**
 * Resolve the raw fan value (number/string/boolean) from a status record.
 */
export function getFanRaw(record) {
  if (!record) return null
  return (
    record.fanOnOrOff ??
    record.fanOnOff ??
    record.fan ??
    record.Fan ??
    record.fanSpeed ??
    record.FanSpeed ??
    null
  )
}

/**
 * Resolve the active blink pattern number from a status record.
 * Returns a number or null.
 */
export function getBlinkPattern(record) {
  if (!record) return null
  const val = record.blinkPattern ?? record.BlinkPattern ?? record.blink_pattern ?? null
  if (val === null || val === undefined) return null
  if (typeof val === 'number') return val
  if (typeof val === 'string') return parseInt(val, 10)
  return null
}

/**
 * Resolve the temperature (°F) from a status record.
 * Returns a finite number or null.
 */
export function getTemperature(record) {
  if (!record) return null
  const val =
    record.temperatureF ??
    record.temperature ??
    record.Temperature ??
    record.temp ??
    record.Temp ??
    null
  if (val === null || val === undefined) return null
  if (typeof val === 'number') return Number.isFinite(val) ? val : null
  if (typeof val === 'string') {
    const parsed = parseFloat(val)
    return isNaN(parsed) ? null : parsed
  }
  return null
}

/**
 * Resolve the Beckhoff message count over the last 24 hours.
 * Returns a non-negative integer (0 when unknown).
 */
export function getMessagesLast24h(record) {
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

/**
 * Resolve the Leuze barcode-reader message count over the last 24 hours.
 * Returns a non-negative integer (0 when unknown).
 */
export function getLuezeMessagesLast24h(record) {
  if (!record) return 0
  const val =
    record.luezeMessagesLast24h ??
    record.LuezeMessagesLast24h ??
    record.lueze_messages_last_24h ??
    null
  if (val === null || val === undefined) return 0
  if (typeof val === 'number') return val
  if (typeof val === 'string') {
    const parsed = parseInt(val, 10)
    return isNaN(parsed) ? 0 : parsed
  }
  return 0
}

/**
 * Derive the overall connection status for a device.
 * Returns 'online' | 'partial' | 'offline'.
 */
export function getConnectionStatus(record) {
  if (!record) return 'offline'
  const beckhoff = getMessagesLast24h(record) > 0
  const lueze = getLuezeMessagesLast24h(record) > 0
  if (beckhoff && lueze) return 'online'
  if (beckhoff || lueze) return 'partial'
  return 'offline'
}

/**
 * Resolve the last barcode scanned by the Leuze reader.
 * Returns a string or null.
 */
export function getLuezeBarcode(record) {
  if (!record) return null
  return (
    record.luezelastReadBarcode ??
    record.luezeLastReadBarcode ??
    record.LuezeLastReadBarcode ??
    null
  )
}

/**
 * Resolve the ingestion timestamp of the last Leuze barcode scan.
 * Returns a string/date value or null.
 */
export function getLuezeIngestionTime(record) {
  if (!record) return null
  return record.luezeBarcodeIngestionTime ?? record.LuezeBarcodeIngestionTime ?? null
}

/** Alias for getLuezeIngestionTime for backwards compatibility. */
export const getLuezeTimestamp = getLuezeIngestionTime

/**
 * Derive the Azure Arc connectivity status for a device.
 * Returns 'connected' | 'partial' | 'offline' | 'not-implemented'.
 *
 * @param {object|null} arcData  - Arc status response from the API
 * @param {number} messagesLast24h      - Beckhoff message count
 * @param {number} luezeMessagesLast24h - Leuze message count
 */
export function deriveAzureStatus(arcData, messagesLast24h, luezeMessagesLast24h) {
  if (!arcData || arcData.error) return 'not-implemented'

  const hostStatus = arcData.host?.status?.toLowerCase() ?? ''
  const vmStatus = arcData.vm?.status?.toLowerCase() ?? ''
  const k8sStatus = arcData.k8sCluster?.status?.toLowerCase() ?? ''

  const allConnected =
    hostStatus === 'connected' && vmStatus === 'connected' && k8sStatus === 'connected'
  const allDisconnected =
    hostStatus === 'disconnected' && vmStatus === 'disconnected' && k8sStatus === 'disconnected'

  if (allConnected && messagesLast24h > 0 && luezeMessagesLast24h > 0) return 'connected'
  if (allDisconnected) return 'offline'
  return 'partial'
}
