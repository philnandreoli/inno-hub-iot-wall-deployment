/**
 * Chat API service — sends user messages to the LLM-powered backend.
 *
 * POST /api/chat
 * Request:  { message, device_id?, conversation_id? }
 * Response: { reply, conversation_id, device_id? }
 */

/**
 * Send a chat message and receive the assistant reply.
 *
 * @param {Object} params
 * @param {string} params.message        - The user's message text.
 * @param {string|null} params.deviceId  - Optional currently-selected device.
 * @param {string|null} params.conversationId - Optional conversation thread ID.
 * @returns {Promise<{reply: string, conversation_id: string, device_id?: string}>}
 */
export async function sendChatMessage({ message, deviceId, conversationId }) {
  const body = { message };
  if (deviceId) body.device_id = deviceId;
  if (conversationId) body.conversation_id = conversationId;

  const response = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    throw new Error(errorData.detail || `Chat error: ${response.status}`);
  }

  return response.json();
}
