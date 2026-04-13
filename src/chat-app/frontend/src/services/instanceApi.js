/**
 * Instance API — fetches available Azure IoT Operations instances.
 *
 * GET /api/instances → { instances: AioInstance[] }
 *
 * @typedef {{
 *   name: string,
 *   resource_group: string,
 *   subscription_id: string,
 *   location: string,
 *   description: string|null
 * }} AioInstance
 */

/**
 * Fetch the list of available AIO instances.
 * @returns {Promise<{instances: AioInstance[]}>}
 */
export async function fetchInstances() {
  const response = await fetch('/api/instances');
  if (!response.ok) throw new Error('Failed to fetch AIO instances');
  return response.json();
}
