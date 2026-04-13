import './App.css';
import { ChatProvider } from './context/ChatContext';
import ChatWindow from './components/ChatWindow';
import DeviceSelector from './components/DeviceSelector';
import DeviceStatePanel from './components/DeviceStatePanel';
import CommandPanel from './components/CommandPanel';

/**
 * App — full operator layout for the IoT Wall Chat application.
 *
 * Layout (CSS Grid):
 * ┌──────────────────────────────────────────────────────┐
 * │  Header                                               │
 * ├────────────────┬─────────────────────────────────────┤
 * │  Sidebar       │  Chat Window                        │
 * │  - Devices     │  - Messages                         │
 * │  - State       │  - Input                            │
 * │  - Commands    │                                     │
 * └────────────────┴─────────────────────────────────────┘
 */
function App() {
  return (
    <ChatProvider>
      <div className="app-layout">
        {/* Header */}
        <header className="app-header" role="banner">
          <h1 className="app-header__title">
            <span className="app-header__icon" aria-hidden="true">⚙</span>
            IoT Operations Chat
          </h1>
          <span className="app-header__subtitle">
            LLM-powered device operations assistant
          </span>
        </header>

        {/* Sidebar */}
        <aside className="app-sidebar" aria-label="Device controls">
          <DeviceSelector />
          <DeviceStatePanel />
          <CommandPanel />
        </aside>

        {/* Main chat area */}
        <main className="app-main">
          <ChatWindow />
        </main>
      </div>
    </ChatProvider>
  );
}

export default App;
