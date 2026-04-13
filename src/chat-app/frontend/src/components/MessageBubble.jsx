/**
 * MessageBubble — renders a single chat message with role-based styling.
 *
 * User messages are right-aligned; assistant messages are left-aligned.
 *
 * @param {{ message: {id:string, role:'user'|'assistant', content:string, timestamp:string} }} props
 */
export default function MessageBubble({ message }) {
  const isUser = message.role === 'user';

  const formattedTime = formatTimestamp(message.timestamp);

  return (
    <div
      className={`message-bubble message-bubble--${message.role}`}
      aria-label={`${isUser ? 'You' : 'Assistant'} said`}
    >
      <div className="message-bubble__content">
        <span className="message-bubble__role">{isUser ? 'You' : 'Assistant'}</span>
        <p className="message-bubble__text">{message.content}</p>
        <time className="message-bubble__time" dateTime={message.timestamp}>
          {formattedTime}
        </time>
      </div>
    </div>
  );
}

/**
 * Format an ISO timestamp into a short locale time string.
 * @param {string} iso
 * @returns {string}
 */
function formatTimestamp(iso) {
  try {
    return new Date(iso).toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return '';
  }
}
