import { useChat } from '../context/ChatContext';
import MessageList from './MessageList';
import ChatInput from './ChatInput';
import LoadingIndicator from './LoadingIndicator';
import ErrorBanner from './ErrorBanner';

/**
 * ChatWindow — main chat area containing message list, loading indicator,
 * error banner, and the input bar.
 */
export default function ChatWindow() {
  const { messages, isLoading, error, sendMessage, clearConversation, dismissError } = useChat();

  return (
    <section className="chat-window" aria-label="Chat conversation">
      {/* Header bar */}
      <header className="chat-window__header">
        <h2 className="chat-window__title">Chat</h2>
        <button
          className="btn btn--ghost"
          onClick={clearConversation}
          aria-label="Clear conversation"
          title="Clear conversation"
        >
          ✕ Clear
        </button>
      </header>

      {/* Error banner */}
      {error && <ErrorBanner message={error} onDismiss={dismissError} />}

      {/* Messages area */}
      <MessageList messages={messages} />

      {/* Loading indicator */}
      {isLoading && <LoadingIndicator />}

      {/* Input bar */}
      <ChatInput onSend={sendMessage} disabled={isLoading} />
    </section>
  );
}
