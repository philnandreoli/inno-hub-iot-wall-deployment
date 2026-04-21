import { ApplicationInsights } from '@microsoft/applicationinsights-web'

let appInsights = null

export function initTelemetry() {
  const connectionString = import.meta.env.VITE_APPINSIGHTS_CONNECTION_STRING
  if (!connectionString) {
    console.warn('[Telemetry] VITE_APPINSIGHTS_CONNECTION_STRING not set — telemetry disabled')
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
