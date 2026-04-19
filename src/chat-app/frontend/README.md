# IoT Control Nexus — Frontend

A production-grade React dashboard for monitoring and controlling IoT devices via the backend API.

## Features

- **Live device grid** — shows all devices grouped by hub
- **Status tiles** — lamp and fan state for each device (auto-refreshes every 30 s)
- **Lamp control** — ON / OFF buttons per device
- **Fan control** — ON / OFF buttons per device
- **Blink patterns** — trigger patterns P1–P5 per device
- **Stats bar** — total devices, active hubs, lamps on, fans active
- **Toast notifications** — command success / failure feedback

## Dev Setup

Make sure the backend is running on `http://localhost:5000` first.

```bash
cd src/chat-app/frontend
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

The Vite dev server proxies `/api` and `/health` to `http://localhost:5000` automatically.

## Build

```bash
npm run build      # outputs to dist/
npm run preview    # preview production build locally
```

## Environment

The API base URL is empty by default (same origin). To point at a remote backend, update `BASE` in `src/api.js`.
