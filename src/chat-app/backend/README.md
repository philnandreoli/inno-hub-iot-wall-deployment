# Backend – IoT Wall Chat App

FastAPI backend for the LLM-powered device operations chat application.

## Prerequisites

- Python 3.11+
- An activated virtual environment (recommended)

## Setup & Run

```bash
# 1. (Optional) Create and activate a virtual environment
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Copy and populate the environment file
cp .env.example .env
# Edit .env with your Azure credentials / endpoints

# 4. Start the development server
uvicorn app.main:app --reload --port 5000
```

The API will be available at <http://localhost:5000>.  
Interactive API docs are at <http://localhost:5000/docs>.

## Environment Variables

See [`.env.example`](.env.example) for all required variables.

| Variable | Description |
|---|---|
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI service endpoint URL |
| `AZURE_OPENAI_DEPLOYMENT` | Model deployment name (e.g. `gpt-4o`) |
| `EVENTHOUSE_MCP_ENDPOINT` | Eventhouse MCP query endpoint |
| `EVENTGRID_ENDPOINT` | Azure Event Grid namespace endpoint |
| `EVENTGRID_TOPIC_PATH` | Event Grid topic path template |
| `INSTANCE_NAME` | Azure IoT Operations instance name |
| `STATE_CACHE_TTL_SECONDS` | Device-state cache TTL in seconds (default 15) |

## Project Layout

```
backend/
├── app/
│   ├── main.py          # FastAPI application + middleware
│   ├── routers/         # Route handlers (one file per domain)
│   ├── services/        # Business logic & Azure client wrappers
│   └── schemas/         # Pydantic request/response models
├── requirements.txt
├── .env.example
└── README.md
```

## Running Tests

```bash
pytest
```
