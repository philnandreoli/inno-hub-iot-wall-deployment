/**
 * Command API service — sends lamp/fan control commands to a device.
 *
 * POST /api/commands/:deviceId
 * Request:  { action: "lamp"|"fan", value: boolean|number }
 * Response: { success: boolean, device_id: string, action: string, message: string }
 */

/**
 * Send a control command to a device.
 *
 * @param {string} deviceId - Target device identifier.
 * @param {string} action   - "lamp" or "fan".
 * @param {boolean|number} value - For lamp: true/false. For fan: 0–32000.
 * @returns {Promise<{success: boolean, device_id: string, action: string, message: string}>}
 */
export async function sendCommand(deviceId, action, value) {
  const response = await fetch(`/api/commands/${encodeURIComponent(deviceId)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, value }),
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new Error(error.detail || `Command failed: ${response.status}`);
  }

  return response.json();
}
