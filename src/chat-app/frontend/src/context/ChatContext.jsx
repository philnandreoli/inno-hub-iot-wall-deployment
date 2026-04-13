import { createContext, useContext, useReducer, useCallback, useMemo } from 'react';
import { sendChatMessage } from '../services/chatApi';

/* ------------------------------------------------------------------ */
/*  State shape & initial values                                       */
/* ------------------------------------------------------------------ */

const initialState = {
  /** @type {{id: string, role: 'user'|'assistant', content: string, timestamp: string}[]} */
  messages: [],
  /** @type {string|null} */
  conversationId: null,
  /** @type {string|null} — name of the selected AIO instance */
  selectedInstanceId: null,
  /** @type {string|null} */
  selectedDeviceId: null,
  /** @type {boolean} */
  isLoading: false,
  /** @type {string|null} */
  error: null,
};

/* ------------------------------------------------------------------ */
/*  Action types                                                       */
/* ------------------------------------------------------------------ */

const ActionTypes = {
  SEND_MESSAGE_START: 'SEND_MESSAGE_START',
  SEND_MESSAGE_SUCCESS: 'SEND_MESSAGE_SUCCESS',
  SEND_MESSAGE_ERROR: 'SEND_MESSAGE_ERROR',
  SET_SELECTED_INSTANCE: 'SET_SELECTED_INSTANCE',
  SET_SELECTED_DEVICE: 'SET_SELECTED_DEVICE',
  CLEAR_CONVERSATION: 'CLEAR_CONVERSATION',
  DISMISS_ERROR: 'DISMISS_ERROR',
};

/* ------------------------------------------------------------------ */
/*  Reducer                                                            */
/* ------------------------------------------------------------------ */

let nextId = 1;
function generateId() {
  return `msg-${Date.now()}-${nextId++}`;
}

function chatReducer(state, action) {
  switch (action.type) {
    case ActionTypes.SEND_MESSAGE_START:
      return {
        ...state,
        isLoading: true,
        error: null,
        messages: [
          ...state.messages,
          {
            id: generateId(),
            role: 'user',
            content: action.payload.message,
            timestamp: new Date().toISOString(),
          },
        ],
      };

    case ActionTypes.SEND_MESSAGE_SUCCESS:
      return {
        ...state,
        isLoading: false,
        conversationId: action.payload.conversation_id,
        messages: [
          ...state.messages,
          {
            id: generateId(),
            role: 'assistant',
            content: action.payload.reply,
            timestamp: new Date().toISOString(),
          },
        ],
      };

    case ActionTypes.SEND_MESSAGE_ERROR:
      return {
        ...state,
        isLoading: false,
        error: action.payload,
      };

    case ActionTypes.SET_SELECTED_INSTANCE:
      return {
        ...state,
        selectedInstanceId: action.payload,
        // Clear device selection when instance changes
        selectedDeviceId: null,
      };

    case ActionTypes.SET_SELECTED_DEVICE:
      return {
        ...state,
        selectedDeviceId: action.payload,
      };

    case ActionTypes.CLEAR_CONVERSATION:
      return {
        ...state,
        messages: [],
        conversationId: null,
        error: null,
      };

    case ActionTypes.DISMISS_ERROR:
      return {
        ...state,
        error: null,
      };

    default:
      return state;
  }
}

/* ------------------------------------------------------------------ */
/*  Context                                                            */
/* ------------------------------------------------------------------ */

const ChatContext = createContext(null);

/**
 * ChatProvider — wraps the application tree with chat state & actions.
 */
export function ChatProvider({ children }) {
  const [state, dispatch] = useReducer(chatReducer, initialState);

  const sendMessage = useCallback(
    async (message) => {
      dispatch({ type: ActionTypes.SEND_MESSAGE_START, payload: { message } });

      try {
        const data = await sendChatMessage({
          message,
          deviceId: state.selectedDeviceId,
          conversationId: state.conversationId,
        });

        dispatch({ type: ActionTypes.SEND_MESSAGE_SUCCESS, payload: data });
      } catch (err) {
        dispatch({
          type: ActionTypes.SEND_MESSAGE_ERROR,
          payload: err.message || 'An unexpected error occurred.',
        });
      }
    },
    [state.selectedDeviceId, state.conversationId],
  );

  const setSelectedInstance = useCallback((instanceName) => {
    dispatch({ type: ActionTypes.SET_SELECTED_INSTANCE, payload: instanceName });
  }, []);

  const setSelectedDevice = useCallback((deviceId) => {
    dispatch({ type: ActionTypes.SET_SELECTED_DEVICE, payload: deviceId });
  }, []);

  const clearConversation = useCallback(() => {
    dispatch({ type: ActionTypes.CLEAR_CONVERSATION });
  }, []);

  const dismissError = useCallback(() => {
    dispatch({ type: ActionTypes.DISMISS_ERROR });
  }, []);

  const value = useMemo(
    () => ({
      ...state,
      sendMessage,
      setSelectedInstance,
      setSelectedDevice,
      clearConversation,
      dismissError,
    }),
    [state, sendMessage, setSelectedInstance, setSelectedDevice, clearConversation, dismissError],
  );

  return <ChatContext.Provider value={value}>{children}</ChatContext.Provider>;
}

/**
 * useChat — convenience hook to consume chat context.
 * @returns {typeof initialState & {
 *   sendMessage: (msg: string) => Promise<void>,
 *   setSelectedInstance: (name: string|null) => void,
 *   setSelectedDevice: (id: string|null) => void,
 *   clearConversation: () => void,
 *   dismissError: () => void,
 * }}
 */
export function useChat() {
  const ctx = useContext(ChatContext);
  if (!ctx) {
    throw new Error('useChat must be used within a ChatProvider');
  }
  return ctx;
}

export default ChatContext;
