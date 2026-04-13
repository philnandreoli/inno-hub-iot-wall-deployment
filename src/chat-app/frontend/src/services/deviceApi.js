/**
 * Device API service — fetches device list and device state from backend.
 *
 * GET /api/devices         → { devices: string[] }
 * GET /api/device-state/:id → DeviceState object
 */

/**
 * Fetch the list of available device IDs.
 * @returns {Promise<{devices: string[]}>}
 */
export async function fetchDevices() {
  const response = await fetch('/api/devices');
  if (!response.ok) {
    throw new Error(`Failed to fetch devices: ${response.status}`);
  }
  return response.json();
}

/**
 * Fetch the operational state of a specific device.
 *
 * @param {string} deviceId
 * @returns {Promise<{
 *   device_id: string,
 *   online: boolean,
 *   lamp: boolean,
 *   fan: number,
 *   temperature: number|null,
 *   vibration: number|null,
 *   error_code: string|null,
 *   last_updated: string
 * }>}
 */
export async function fetchDeviceState(deviceId) {
  const response = await fetch(`/api/device-state/${encodeURIComponent(deviceId)}`);
  if (!response.ok) {
    throw new Error(`Failed to fetch device state: ${response.status}`);
  }
  return response.json();
}
