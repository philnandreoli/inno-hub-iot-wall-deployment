import { useEffect, useRef } from 'react';
import MessageBubble from './MessageBubble';

/**
 * MessageList — scrollable list of chat messages with auto-scroll.
 *
 * @param {{ messages: Array<{id:string,role:string,content:string,timestamp:string}> }} props
 */
export default function MessageList({ messages }) {
  const bottomRef = useRef(null);

  // Auto-scroll to the newest message whenever the list changes.
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  if (messages.length === 0) {
    return (
      <div className="message-list message-list--empty" role="log" aria-live="polite" aria-label="Chat messages">
        <div className="message-list__placeholder">
          <span className="message-list__placeholder-icon" aria-hidden="true">💬</span>
          <p>No messages yet. Start a conversation!</p>
        </div>
      </div>
    );
  }

  return (
    <div className="message-list" role="log" aria-live="polite" aria-label="Chat messages">
      {messages.map((msg) => (
        <MessageBubble key={msg.id} message={msg} />
      ))}
      <div ref={bottomRef} aria-hidden="true" />
    </div>
  );
}
