import { ApplicationInsights } from '@microsoft/applicationinsights-web'

let appInsights = null

export function initTelemetry() {
  // In local dev, VITE_APPINSIGHTS_CONNECTION_STRING can be set in .env.local.
  // In production, docker-entrypoint.sh replaces the __APPINSIGHTS_CONNECTION_STRING__
  // placeholder in index.html (window.__APP_CONFIG__) at container start from the runtime
  // env var, so the secret is never baked into the image layer.
  const runtimeConfig = (typeof window !== 'undefined' && window.__APP_CONFIG__) || {}
  const connectionString =
    runtimeConfig.appInsightsConnectionString ||
    import.meta.env.VITE_APPINSIGHTS_CONNECTION_STRING
  if (!connectionString || connectionString === '__APPINSIGHTS_CONNECTION_STRING__') {
    console.warn('[Telemetry] App Insights connection string not configured — telemetry disabled')
    return null
  }

  appInsights = new ApplicationInsights({
    config: {
      connectionString,
      enableAutoRouteTracking: false, // SPA with no router — tracked manually
      enableCorsCorrelation: true,
      enableRequestHeaderTracking: true,
      enableResponseHeaderTracking: true,
      enableAjaxPerfTracking: true,
      enableUnhandledPromiseRejectionTracking: true,
      disableFetchTracking: false,
      autoTrackPageVisitTime: true,
    },
  })

  appInsights.loadAppInsights()
  appInsights.trackPageView({ name: document.title })

  return appInsights
}

export function setAuthenticatedUser(accountId, accountName) {
  if (!appInsights) return
  appInsights.setAuthenticatedUserContext(accountId, undefined, true)
  appInsights.context.user.accountId = accountName || accountId
}

export function clearAuthenticatedUser() {
  if (!appInsights) return
  appInsights.clearAuthenticatedUserContext()
}

export function trackEvent(name, properties) {
  if (!appInsights) return
  appInsights.trackEvent({ name }, properties)
}

export function trackException(error, properties) {
  if (!appInsights) return
  appInsights.trackException({ exception: error }, properties)
}

export function getAppInsights() {
  return appInsights
}
