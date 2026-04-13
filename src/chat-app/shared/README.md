# Shared – Cross-Cutting Types & Contracts

This directory contains documentation and definitions for data contracts that are
shared between the **backend** (FastAPI / Python) and the **frontend** (React / JS).

## Purpose

- Provide a single source of truth for request/response shapes used by the chat API.
- Prevent drift between backend Pydantic schemas and frontend TypeScript / JSDoc types.
- Document event structures published to Azure Event Grid and consumed by IoT Operations.

## Contents

| File | Description |
|---|---|
| [`types.md`](./types.md) | Human-readable documentation of all shared data contracts |

## Usage

- **Backend:** Implement contracts as Pydantic models in `backend/app/schemas/`.
- **Frontend:** Reference contracts when building API calls in `frontend/src/`.
- **Contract changes:** Update `types.md` first, then update both implementations together.
