# Frontend – IoT Wall Chat App

React + Vite frontend for the LLM-powered device operations chat application.

## Prerequisites

- Node.js 18+
- npm 9+ (bundled with Node.js 18)

## Setup & Run

```bash
# 1. Install dependencies
npm install

# 2. Start the development server (hot-reload on port 3000)
npm run dev
```

The app will be available at <http://localhost:3000>.

> **Note:** The Vite dev server proxies `/api/*` and `/health` requests to the
> FastAPI backend running on port 5000. Start the backend first to avoid
> connection errors.

## Available Scripts

| Command | Description |
|---|---|
| `npm run dev` | Start dev server with HMR on port 3000 |
| `npm run build` | Production build into `dist/` |
| `npm run preview` | Preview the production build locally |
| `npm run lint` | Run ESLint across all JS/JSX files |

## Project Layout

```
frontend/
├── index.html           # HTML entry point
├── vite.config.js       # Vite config (dev proxy → port 5000)
├── package.json
├── src/
│   ├── main.jsx         # React DOM mount
│   ├── App.jsx          # Root application component (placeholder)
│   ├── App.css          # Component styles
│   └── index.css        # Global styles / reset
└── README.md
```
