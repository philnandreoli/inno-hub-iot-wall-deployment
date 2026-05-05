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

export async function fetchDeviceTelemetry(deviceName, timespan = '7d', startDate = null, endDate = null) {
  const params = new URLSearchParams()
  if (startDate && endDate) {
    params.set('startDate', startDate)
    params.set('endDate', endDate)
  } else if (timespan) {
    params.set('timespan', timespan)
  }
  const url = `${BASE}/api/devices/${encodeURIComponent(deviceName)}/telemetry?${params}`
  const maxRetries = 3
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 120_000)
    try {
      const res = await authFetch(url, { signal: controller.signal })
      clearTimeout(timeoutId)
      if (!res.ok) throw new Error(`Telemetry fetch failed: ${res.status}`)
      return await res.json()
    } catch (err) {
      clearTimeout(timeoutId)
      if (attempt < maxRetries - 1 && (err.name === 'AbortError' || err.name === 'TypeError')) {
        await new Promise(r => setTimeout(r, 1000 * 2 ** attempt))
        continue
      }
      throw err
    }
  }
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

export async function fetchDeviceArcStatus(deviceName) {
  const res = await authFetch(`${BASE}/api/devices/${encodeURIComponent(deviceName)}/arc-status`)
  if (!res.ok) throw new Error(`Arc status fetch failed: ${res.status}`)
  return res.json()
}

export async function sendChatMessage(sessionId, message) {
  const res = await authFetch(`${BASE}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, message }),
  })
  if (!res.ok) throw new Error(`Chat request failed: ${res.status}`)
  return res.json()
}

export async function confirmChatAction(sessionId) {
  const res = await authFetch(`${BASE}/api/chat/confirm`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId }),
  })
  if (!res.ok) throw new Error(`Confirm action failed: ${res.status}`)
  return res.json()
}

export async function cancelChatAction(sessionId) {
  const res = await authFetch(`${BASE}/api/chat/cancel`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId }),
  })
  if (!res.ok) throw new Error(`Cancel action failed: ${res.status}`)
  return res.json()
}
