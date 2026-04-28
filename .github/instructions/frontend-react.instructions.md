---
applyTo: "src/chat-app/frontend/**"
description: "Use when writing or modifying React frontend code — components, API calls, auth, styling, or configuration."
---
# Frontend React Guidelines

## Patterns

- Functional components only with named exports (`export function ComponentName(...)`)
- `App.jsx` is the only default export
- Props destructured in function parameters
- State management with `useState`/`useEffect`/`useCallback` — no external state library
- Manual URL routing via `window.history.pushState` and `popstate` — no React Router

## API Integration

- All API calls go through `authFetch()` in `api.js` which injects Bearer tokens
- Token acquisition uses `acquireTokenSilent` with redirect fallback
- Backend URL comes from `VITE_API_BASE_URL` environment variable

## Auth (MSAL)

- Azure Entra ID via `@azure/msal-browser` and `@azure/msal-react`
- Config reads from `VITE_AZURE_CLIENT_ID` and `VITE_AZURE_TENANT_ID`
- Redirect flow (not popup)
- App wrapped in `<MsalProvider>` in `main.jsx`

## Styling

- Single `index.css` file with CSS custom properties (design tokens)
- Dark theme is default; light theme via `[data-theme='light']` selector
- Semantic variable names: `--bg-void`, `--cyan`, `--text-primary`, etc.
- Fonts: Bebas Neue (display), Rajdhani (UI), JetBrains Mono (monospace)
- No CSS modules, Tailwind, or CSS-in-JS

## Deployment

- Multi-stage Docker build: Node 22 Alpine → Nginx Alpine
- `docker-entrypoint.sh` replaces `__BACKEND_URL__` placeholder at runtime via `sed`
- Nginx handles SPA fallback and reverse-proxies `/api/` to backend
