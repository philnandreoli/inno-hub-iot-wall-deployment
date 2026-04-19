import { tokenRequest } from './authConfig.js'

const BASE = ''

let _msalInstance = null

export function setMsalInstance(instance) {
  _msalInstance = instance
}

async function getAuthHeaders() {
  if (!_msalInstance) return {}
  const account = _msalInstance.getActiveAccount()
  if (!account) return {}
  try {
    const resp = await _msalInstance.acquireTokenSilent({
      ...tokenRequest,
      account,
    })
    return { Authorization: `Bearer ${resp.accessToken}` }
  } catch {
    // If silent fails, fall back to redirect (e.g. expired session)
    _msalInstance.acquireTokenRedirect(tokenRequest)
    return {}
  }
}

async function authFetch(url, options = {}) {
  const headers = { ...options.headers, ...(await getAuthHeaders()) }
  return fetch(url, { ...options, headers })
}

export async function fetchDevicesByHub() {
  const res = await authFetch(`${BASE}/api/devices/by-hub`)
  if (!res.ok) throw new Error(`Failed to fetch devices: ${res.status}`)
  return res.json()
}

export async function fetchAllDevicesStatus() {
  const res = await authFetch(`${BASE}/api/devices/commands/status`)
  if (!res.ok) throw new Error(`Failed to fetch statuses: ${res.status}`)
  return res.json()
}

export async function fetchDeviceStatus(deviceName) {
  const res = await authFetch(`${BASE}/api/devices/${encodeURIComponent(deviceName)}/commands/status`)
  if (!res.ok) throw new Error(`Status fetch failed: ${res.status}`)
  return res.json()
}

export async function fetchDeviceTelemetry(deviceName, timespan = '7d') {
  const res = await authFetch(
    `${BASE}/api/devices/${encodeURIComponent(deviceName)}/telemetry?timespan=${encodeURIComponent(timespan)}`,
  )
  if (!res.ok) throw new Error(`Telemetry fetch failed: ${res.status}`)
  return res.json()
}

export async function sendLampOn(deviceName) {
  const res = await authFetch(`${BASE}/api/devices/${encodeURIComponent(deviceName)}/commands/lamp/on`, { method: 'POST' })
  if (!res.ok) throw new Error(`Lamp on failed: ${res.status}`)
  return res.json()
}

export async function sendLampOff(deviceName) {
  const res = await authFetch(`${BASE}/api/devices/${encodeURIComponent(deviceName)}/commands/lamp/off`, { method: 'POST' })
  if (!res.ok) throw new Error(`Lamp off failed: ${res.status}`)
  return res.json()
}

export async function sendFanOn(deviceName) {
  const res = await authFetch(`${BASE}/api/devices/${encodeURIComponent(deviceName)}/commands/fan/on`, { method: 'POST' })
  if (!res.ok) throw new Error(`Fan on failed: ${res.status}`)
  return res.json()
}

export async function sendFanOff(deviceName) {
  const res = await authFetch(`${BASE}/api/devices/${encodeURIComponent(deviceName)}/commands/fan/off`, { method: 'POST' })
  if (!res.ok) throw new Error(`Fan off failed: ${res.status}`)
  return res.json()
}

export async function sendBlinkPattern(deviceName, patternNumber) {
  const res = await authFetch(
    `${BASE}/api/devices/${encodeURIComponent(deviceName)}/commands/blinkpattern/${patternNumber}`,
    { method: 'POST' },
  )
  if (!res.ok) throw new Error(`Blink pattern failed: ${res.status}`)
  return res.json()
}
