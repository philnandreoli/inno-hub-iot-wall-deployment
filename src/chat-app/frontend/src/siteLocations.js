/**
 * Hub-code → friendly city label mapping.
 * Coordinates come from the API (LATITUDE / LONGITUDE fields).
 */

const HUB_LABELS = {
  BOS: 'Boston',
  CHI: 'Chicago',
  DET: 'Detroit',
  MSP: 'Minneapolis',
  NYC: 'New York City',
  PHI: 'Philadelphia',
  SEA: 'Seattle',
  STL: 'St. Louis',
}

/**
 * Return a friendly city name for a hub code, or the code itself as fallback.
 */
export function getCityForHub(hubCode) {
  if (!hubCode) return 'Unknown'
  return HUB_LABELS[hubCode.toUpperCase()] ?? hubCode
}

/**
 * Extract latitude from a device record.
 */
export function getLatitude(device) {
  const val = device?.LATITUDE ?? device?.latitude ?? device?.Latitude ?? device?.lat ?? null
  if (val === null || val === undefined) return null
  const n = typeof val === 'number' ? val : parseFloat(val)
  return Number.isFinite(n) ? n : null
}

/**
 * Extract longitude from a device record.
 */
export function getLongitude(device) {
  const val = device?.LONGITUDE ?? device?.longitude ?? device?.Longitude ?? device?.lng ?? null
  if (val === null || val === undefined) return null
  const n = typeof val === 'number' ? val : parseFloat(val)
  return Number.isFinite(n) ? n : null
}

/**
 * Extract hub code from a device record.
 */
export function getHub(device) {
  return device?.hub ?? device?.Hub ?? device?.hubName ?? device?.HubName ?? null
}
