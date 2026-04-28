# Project Guidelines

## Overview

This is an Azure IoT Operations deployment toolkit with a web dashboard ("IoT Control Nexus") for monitoring and commanding industrial devices (Beckhoff PLCs, Leuze barcode readers) via MQTT through Azure Event Grid.

## Architecture

- **Bash scripts** (`v1/`, `v2/`): Sequential provisioning steps for Azure IoT Operations on Ubuntu hosts (Arc-enable, VM creation, k3s, IoT Ops deployment)
- **Backend** (`src/chat-app/backend/`): Python 3.11, FastAPI, MQTT publishing to Azure Event Grid, telemetry reads from Microsoft Fabric Eventhouse (Kusto)
- **Frontend** (`src/chat-app/frontend/`): React 18 + Vite, MSAL auth, Leaflet maps, single CSS file with design tokens

## Build and Test

### Backend
```bash
cd src/chat-app/backend
pip install -r requirements.txt
pytest tests/
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### Frontend
```bash
cd src/chat-app/frontend
npm ci
npm run build
npm run dev
```

## Conventions

- No SQLAlchemy or Alembic — data access is via Kusto queries to Microsoft Fabric Eventhouse
- Azure auth uses Entra ID (formerly Azure AD) with MSAL on frontend and JWT token verification on backend
- Environment variables follow `APP_` prefix on backend, `VITE_` prefix on frontend
- CI/CD uses OIDC workload identity federation — no stored Azure secrets
- Docker images target `linux/amd64` only
