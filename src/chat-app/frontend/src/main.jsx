import React from 'react'
import ReactDOM from 'react-dom/client'
import { PublicClientApplication, EventType } from '@azure/msal-browser'
import { MsalProvider } from '@azure/msal-react'
import { msalConfig } from './authConfig.js'
import { initTelemetry } from './telemetry.js'
import { ErrorBoundary } from './components/ErrorBoundary.jsx'
import App from './App.jsx'
import './index.css'

// Initialize Application Insights early so it captures page load metrics
initTelemetry()

const msalInstance = new PublicClientApplication(msalConfig)

// Set the first account as active after login so acquireTokenSilent works automatically.
msalInstance.addEventCallback((event) => {
  if (event.eventType === EventType.LOGIN_SUCCESS && event.payload?.account) {
    msalInstance.setActiveAccount(event.payload.account)
  }
})

function renderApp() {
  ReactDOM.createRoot(document.getElementById('root')).render(
    <React.StrictMode>
      <ErrorBoundary>
        <MsalProvider instance={msalInstance}>
          <App />
        </MsalProvider>
      </ErrorBoundary>
    </React.StrictMode>,
  )
}

function renderError(err) {
  console.error('[MSAL init error]', err)
  document.getElementById('root').innerHTML =
    '<div style="color:#ff6b6b;font-family:monospace;padding:2rem;">' +
    '<h2>Authentication init failed</h2>' +
    '<pre>' + (err?.message || err) + '</pre>' +
    '<p style="color:#ccc;margin-top:1rem;">Check browser console and verify VITE_AZURE_CLIENT_ID / VITE_AZURE_TENANT_ID in your .env file.</p>' +
    '</div>'
}

// Ensure initialization completes before rendering.
msalInstance.initialize().then(() => {
  // Handle redirect promise (no-op when not returning from redirect).
  msalInstance.handleRedirectPromise().then(() => {
    // If no active account, pick the first one (e.g. after page refresh).
    if (!msalInstance.getActiveAccount() && msalInstance.getAllAccounts().length > 0) {
      msalInstance.setActiveAccount(msalInstance.getAllAccounts()[0])
    }
  }).catch((err) => {
    // Redirect handling can fail after a bad login attempt — log and continue.
    console.warn('[MSAL] handleRedirectPromise error (rendering app anyway):', err)
  }).finally(() => {
    renderApp()
  })
}).catch(renderError)
