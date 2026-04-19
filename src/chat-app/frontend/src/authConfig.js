import { LogLevel } from '@azure/msal-browser'

const clientId = import.meta.env.VITE_AZURE_CLIENT_ID || ''
const tenantId = import.meta.env.VITE_AZURE_TENANT_ID || 'common'

export const msalConfig = {
  auth: {
    clientId,
    authority: `https://login.microsoftonline.com/${tenantId}`,
    redirectUri: window.location.origin,
    postLogoutRedirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: 'localStorage',
    storeAuthStateInCookie: false,
  },
  system: {
    loggerOptions: {
      logLevel: LogLevel.Verbose,
      loggerCallback: (_level, message, containsPii) => {
        if (!containsPii) console.debug('[MSAL]', message)
      },
    },
  },
}

// Scopes requested when acquiring tokens for the backend API.
// Set VITE_AZURE_API_SCOPE to your App Registration's exposed API scope,
// e.g. "api://<client-id>/access_as_user"
const apiScope = import.meta.env.VITE_AZURE_API_SCOPE

export const loginRequest = {
  scopes: apiScope ? [apiScope] : ['User.Read'],
}

export const tokenRequest = {
  scopes: apiScope ? [apiScope] : ['User.Read'],
}
