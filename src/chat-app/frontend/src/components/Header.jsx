export function Header({ connectionOk, loading, onRefresh, theme, onToggleTheme, userName, onSignOut }) {
  const isLightMode = theme === 'light'

  return (
    <header className="site-header">
      <div className="header-inner">
        <div className="header-logo">
          <div className="logo-icon">
            <svg viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
              <polygon
                points="20,2 38,11 38,29 20,38 2,29 2,11"
                stroke="var(--cyan)"
                strokeWidth="1.5"
                fill="var(--logo-fill)"
              />
              <circle cx="20" cy="20" r="5" fill="var(--cyan)" opacity="0.9" />
              <line x1="20" y1="2" x2="20" y2="15" stroke="var(--cyan)" strokeWidth="1" opacity="0.5" />
              <line x1="20" y1="25" x2="20" y2="38" stroke="var(--cyan)" strokeWidth="1" opacity="0.5" />
              <line x1="2" y1="11" x2="15.5" y2="17.5" stroke="var(--cyan)" strokeWidth="1" opacity="0.5" />
              <line x1="24.5" y1="22.5" x2="38" y2="29" stroke="var(--cyan)" strokeWidth="1" opacity="0.5" />
              <line x1="38" y1="11" x2="24.5" y2="17.5" stroke="var(--cyan)" strokeWidth="1" opacity="0.5" />
              <line x1="15.5" y1="22.5" x2="2" y2="29" stroke="var(--cyan)" strokeWidth="1" opacity="0.5" />
            </svg>
          </div>
          <div className="logo-text">
            <span className="logo-title">IoT Control Nexus</span>
            <span className="logo-subtitle">Device Operations Dashboard</span>
          </div>
        </div>

        <div className="header-meta">
          <div className="connection-status">
            <span
              className={`status-led ${loading ? 'loading' : connectionOk ? 'online' : 'offline'}`}
            />
            {loading ? 'syncing' : connectionOk ? 'connected' : 'disconnected'}
          </div>
          <button
            type="button"
            className="theme-btn"
            onClick={onToggleTheme}
            aria-label={`Switch to ${isLightMode ? 'dark' : 'light'} mode`}
            aria-pressed={isLightMode}
            title={`Switch to ${isLightMode ? 'dark' : 'light'} mode`}
          >
            <span className="theme-btn-icon" aria-hidden="true">
              {isLightMode ? '☼' : '◐'}
            </span>
            <span className="theme-btn-text">
              {isLightMode ? 'Dark Mode' : 'Light Mode'}
            </span>
          </button>
          <button className="refresh-btn" onClick={onRefresh} disabled={loading}>
            <svg
              className={`refresh-icon${loading ? ' spinning' : ''}`}
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <polyline points="23 4 23 10 17 10" />
              <polyline points="1 20 1 14 7 14" />
              <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15" />
            </svg>
            Refresh
          </button>
          {userName && (
            <span className="user-greeting">
              {userName}
            </span>
          )}
          {onSignOut && (
            <button type="button" className="signout-btn" onClick={onSignOut}>
              Sign out
            </button>
          )}
        </div>
      </div>
    </header>
  )
}
