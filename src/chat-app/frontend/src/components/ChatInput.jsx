import { useState, useCallback } from 'react';

/**
 * ChatInput — text input with Send button.
 * Prevents empty sends and disables while loading.
 *
 * @param {{ onSend: (msg: string) => void, disabled: boolean }} props
 */
export default function ChatInput({ onSend, disabled }) {
  const [text, setText] = useState('');

  const handleSubmit = useCallback(
    (e) => {
      e.preventDefault();
      const trimmed = text.trim();
      if (!trimmed || disabled) return;
      onSend(trimmed);
      setText('');
    },
    [text, disabled, onSend],
  );

  return (
    <form className="chat-input" onSubmit={handleSubmit} aria-label="Send a message">
      <label htmlFor="chat-input-field" className="sr-only">
        Type your message
      </label>
      <input
        id="chat-input-field"
        className="chat-input__field"
        type="text"
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="Type a message…"
        disabled={disabled}
        autoComplete="off"
        aria-disabled={disabled}
      />
      <button
        className="btn btn--primary chat-input__send"
        type="submit"
        disabled={disabled || text.trim().length === 0}
        aria-label="Send message"
      >
        Send
      </button>
    </form>
  );
}
