import { useEffect, useRef, useState, useCallback } from 'react'
import { sendChatMessage, confirmChatAction, cancelChatAction } from '../api.js'

const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition

function getOrCreateSessionId() {
  let id = sessionStorage.getItem('iot-chat-session')
  if (!id) {
    id = crypto.randomUUID()
    sessionStorage.setItem('iot-chat-session', id)
  }
  return id
}

function MessageBubble({ msg }) {
  const isUser = msg.role === 'user'
  const isSystem = msg.role === 'system'
  return (
    <div className={`chat-bubble-row ${isUser ? 'chat-bubble-row--user' : 'chat-bubble-row--assistant'}`}>
      <div className={`chat-bubble ${isUser ? 'chat-bubble--user' : isSystem ? 'chat-bubble--system' : 'chat-bubble--assistant'}`}>
        <span className="chat-bubble-role">{isUser ? 'You' : 'AI'}</span>
        <p className="chat-bubble-text">{msg.content}</p>
      </div>
    </div>
  )
}

function ConfirmationButtons({ action, onConfirm, onCancel, loading }) {
  return (
    <div className="chat-bubble-row chat-bubble-row--assistant">
      <div className="chat-bubble chat-bubble--assistant chat-confirm-inline">
        <div className="chat-confirm-description">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--amber)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>
            <line x1="12" y1="9" x2="12" y2="13"/>
            <line x1="12" y1="17" x2="12.01" y2="17"/>
          </svg>
          <span>{action.description}</span>
        </div>
        <div className="chat-confirm-actions">
          <button
            type="button"
            className="chat-confirm-btn chat-confirm-btn--cancel"
            onClick={onCancel}
            disabled={loading}
          >
            Cancel
          </button>
          <button
            type="button"
            className="chat-confirm-btn chat-confirm-btn--confirm"
            onClick={onConfirm}
            disabled={loading}
          >
            {loading ? (
              <span className="chat-spinner" aria-label="Processing" />
            ) : (
              'Confirm'
            )}
          </button>
        </div>
      </div>
    </div>
  )
}

export function ChatPanel({ isOpen, onClose, onCommandExecuted, deviceContext }) {
  const initialMessage = {
    role: 'assistant',
    content: 'Hello! I can help you control and monitor your IoT devices. Try asking "What is the status of [device-name]?" or "Turn the lamp on for [device-name]".',
  }

  const [messages, setMessages] = useState([initialMessage])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const [pendingAction, setPendingAction] = useState(null)
  const [confirmLoading, setConfirmLoading] = useState(false)
  const [sessionId, setSessionId] = useState(getOrCreateSessionId)
  const [isListening, setIsListening] = useState(false)
  const bottomRef = useRef(null)
  const inputRef = useRef(null)
  const recognitionRef = useRef(null)

  useEffect(() => {
    if (isOpen && inputRef.current) {
      inputRef.current.focus()
    }
  }, [isOpen])

  useEffect(() => {
    return () => {
      if (recognitionRef.current) {
        recognitionRef.current.abort()
      }
    }
  }, [])

  function handleNewChat() {
    const newId = crypto.randomUUID()
    sessionStorage.setItem('iot-chat-session', newId)
    setSessionId(newId)
    setMessages([initialMessage])
    setPendingAction(null)
    setInput('')
    setLoading(false)
    setConfirmLoading(false)
    if (recognitionRef.current) {
      recognitionRef.current.abort()
      setIsListening(false)
    }
  }

  const toggleListening = useCallback(() => {
    if (!SpeechRecognition) return

    if (isListening) {
      recognitionRef.current?.stop()
      setIsListening(false)
      return
    }

    const recognition = new SpeechRecognition()
    recognition.continuous = true
    recognition.interimResults = false
    recognition.lang = 'en-US'

    recognition.onresult = (event) => {
      let transcript = ''
      for (let i = event.resultIndex; i < event.results.length; i++) {
        if (event.results[i].isFinal) {
          transcript += event.results[i][0].transcript
        }
      }
      if (transcript) {
        setInput(prev => prev ? `${prev} ${transcript}` : transcript)
      }
    }
    recognition.onerror = () => setIsListening(false)
    recognition.onend = () => setIsListening(false)

    recognitionRef.current = recognition
    recognition.start()
    setIsListening(true)
  }, [isListening])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, pendingAction])

  async function handleSend() {
    const text = input.trim()
    if (!text || loading) return

    setInput('')
    setMessages(prev => [...prev, { role: 'user', content: text }])
    setLoading(true)

    try {
      const data = await sendChatMessage(sessionId, text, deviceContext)
      if (!data.pendingAction) {
        setMessages(prev => [...prev, { role: 'assistant', content: data.message }])
      }
      setPendingAction(data.pendingAction ?? null)
    } catch (err) {
      setMessages(prev => [
        ...prev,
        { role: 'assistant', content: `Sorry, something went wrong: ${err.message}` },
      ])
    } finally {
      setLoading(false)
    }
  }

  async function handleConfirm() {
    setConfirmLoading(true)
    try {
      const data = await confirmChatAction(sessionId)
      setPendingAction(null)
      setMessages(prev => [...prev, { role: 'assistant', content: data.message }])
      if (onCommandExecuted) {
        // Delay refresh to allow the device time to process the command
        setTimeout(() => onCommandExecuted(), 3000)
      }
    } catch (err) {
      setPendingAction(null)
      setMessages(prev => [
        ...prev,
        { role: 'assistant', content: `Command failed: ${err.message}` },
      ])
    } finally {
      setConfirmLoading(false)
    }
  }

  async function handleCancel() {
    setConfirmLoading(true)
    try {
      const data = await cancelChatAction(sessionId)
      setPendingAction(null)
      setMessages(prev => [...prev, { role: 'assistant', content: data.message }])
    } catch {
      setPendingAction(null)
      setMessages(prev => [
        ...prev,
        { role: 'assistant', content: 'Command cancelled.' },
      ])
    } finally {
      setConfirmLoading(false)
    }
  }

  function handleKeyDown(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  if (!isOpen) return null

  return (
      <div className="chat-panel" role="complementary" aria-label="Nexus AI assistant">
        <div className="chat-panel-header">
          <div className="chat-panel-header-title">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--cyan)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/>
            </svg>
            <span>Nexus AI</span>
          </div>
          <div className="chat-panel-header-actions">
          <button
            type="button"
            className="chat-panel-new"
            onClick={handleNewChat}
            disabled={messages.length <= 1 && !pendingAction}
            aria-label="New chat"
            title="New chat"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M12 20h9"/>
              <path d="M16.5 3.5a2.121 2.121 0 013 3L7 19l-4 1 1-4L16.5 3.5z"/>
            </svg>
          </button>
          <button
            type="button"
            className="chat-panel-close"
            onClick={onClose}
            aria-label="Close chat panel"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <line x1="18" y1="6" x2="6" y2="18"/>
              <line x1="6" y1="6" x2="18" y2="18"/>
            </svg>
          </button>
          </div>
        </div>

        <div className="chat-messages" aria-live="polite" aria-atomic="false">
          {messages.map((msg, i) => (
            <MessageBubble key={i} msg={msg} />
          ))}
          {pendingAction && (
            <ConfirmationButtons
              action={pendingAction}
              onConfirm={handleConfirm}
              onCancel={handleCancel}
              loading={confirmLoading}
            />
          )}
          {loading && (
            <div className="chat-bubble-row chat-bubble-row--assistant">
              <div className="chat-bubble chat-bubble--assistant chat-bubble--typing">
                <span className="chat-typing-dot" />
                <span className="chat-typing-dot" />
                <span className="chat-typing-dot" />
              </div>
            </div>
          )}
          <div ref={bottomRef} />
        </div>

        <div className="chat-input-row">
          <textarea
            ref={inputRef}
            className="chat-input"
            rows={1}
            placeholder="Ask about a device or issue a command…"
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            disabled={loading || !!pendingAction}
            aria-label="Chat input"
          />
          {SpeechRecognition && (
            <button
              type="button"
              className={`chat-mic-btn${isListening ? ' chat-mic-btn--active' : ''}`}
              onClick={toggleListening}
              disabled={loading || !!pendingAction}
              aria-label={isListening ? 'Stop listening' : 'Start voice input'}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M12 1a3 3 0 00-3 3v8a3 3 0 006 0V4a3 3 0 00-3-3z"/>
                <path d="M19 10v2a7 7 0 01-14 0v-2"/>
                <line x1="12" y1="19" x2="12" y2="23"/>
                <line x1="8" y1="23" x2="16" y2="23"/>
              </svg>
            </button>
          )}
          <button
            type="button"
            className="chat-send-btn"
            onClick={handleSend}
            disabled={loading || !input.trim() || !!pendingAction}
            aria-label="Send message"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <line x1="22" y1="2" x2="11" y2="13"/>
              <polygon points="22 2 15 22 11 13 2 9 22 2"/>
            </svg>
          </button>
        </div>
      </div>
  )
}
