import { useMsal } from '@azure/msal-react'
import { loginRequest } from '../authConfig.js'

export function LoginPage() {
  const { instance } = useMsal()

  const handleLogin = () => {
    instance.loginRedirect(loginRequest).catch(err => {
      console.error('Login failed:', err)
    })
  }

  return (
    <div className="login-wrapper">
      <div className="login-card">
        {/* Logo — same as header */}
        <div className="login-logo">
          <svg viewBox="0 0 40 40" width="72" height="72" fill="none" xmlns="http://www.w3.org/2000/svg">
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

        <h1 className="login-title">IoT Control Nexus</h1>
        <p className="login-subtitle">Device Operations Dashboard</p>

        <div className="login-divider" />

        <p className="login-prompt">Sign in with your organization account to continue.</p>

        <button
          type="button"
          className="login-btn"
          onClick={handleLogin}
        >
          <svg width="20" height="20" viewBox="0 0 21 21" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
            <rect x="1" y="1" width="9" height="9" fill="currentColor" />
            <rect x="11" y="1" width="9" height="9" fill="currentColor" opacity="0.7" />
            <rect x="1" y="11" width="9" height="9" fill="currentColor" opacity="0.7" />
            <rect x="11" y="11" width="9" height="9" fill="currentColor" opacity="0.4" />
          </svg>
          Sign in with Microsoft
        </button>
      </div>
    </div>
  )
}
