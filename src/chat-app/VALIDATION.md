# IoT Wall Chat App — End-to-End Validation Checklist

> **ISSUE-014** | Reproducible E2E validation guide for the `src/chat-app` application
> running inside the VS Code DevContainer. Work through each section in order; check off
> every item before considering a scenario complete.

---

## Prerequisites Checklist

Confirm all of the following before starting the DevContainer:

- [ ] Docker Desktop is installed and running
- [ ] VS Code is installed with the
      [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
      (`ms-vscode-remote.remote-containers`)
- [ ] Azure CLI is authenticated on the host machine (`az login` — check with `az account show`)
- [ ] Required Azure resources are provisioned:
  - [ ] Azure OpenAI Service with a `gpt-4o` or `gpt-4-turbo` deployment
  - [ ] Fabric EventHouse with the MCP REST endpoint reachable
  - [ ] Azure Event Grid custom topic created
- [ ] Environment variables are set on the host (see `DEPLOYMENT.md §3`):
  - [ ] `AZURE_OPENAI_ENDPOINT`
  - [ ] `AZURE_OPENAI_DEPLOYMENT`
  - [ ] `EVENTHOUSE_MCP_ENDPOINT`
  - [ ] `EVENTGRID_MQTT_HOSTNAME`
  - [ ] `INSTANCE_NAME`

---

## Setup Steps

### 1. Open the Repository in VS Code

```bash
code /path/to/inno-hub-iot-wall-deployment
```

### 2. Reopen in DevContainer

When VS Code shows the notification *"Folder contains a Dev Container configuration file"*,
click **Reopen in Container**.

Alternatively, open the Command Palette (`Ctrl/Cmd+Shift+P`) and run:
```
Dev Containers: Reopen in Container
```

### 3. Wait for Container Build and `postCreateCommand`

The first build takes 3–5 minutes. VS Code displays progress in the terminal panel.
The `postCreateCommand` runs automatically and installs all dependencies:

```
cd src/chat-app/backend && pip install -r requirements.txt
cd ../frontend && npm install
```

Wait for it to complete before continuing.

### 4. Create `.env` File in the Backend Directory

Open an integrated terminal inside the container and run:

```bash
cp src/chat-app/backend/.env.example src/chat-app/backend/.env
```

Edit the file and fill in all required values. If you passed environment variables via
`${localEnv:…}` in `devcontainer.json`, this step is optional but recommended for
`STATE_CACHE_TTL_SECONDS` and any values not covered by `remoteEnv`.

### 5. Verify Backend Import

```bash
cd src/chat-app/backend
python -c "from app.main import app; print('Backend OK')"
```

**Expected output:**
```
Backend OK
```

If you see an `ImportError` or `ModuleNotFoundError`, confirm that `pip install -r requirements.txt`
completed successfully.

### 6. Verify Node is Available

```bash
cd src/chat-app/frontend
node -e "console.log('Node OK')"
```

**Expected output:**
```
Node OK
```

---

## Start Services

Open two separate integrated terminals in VS Code.

```bash
# ── Terminal 1 — Backend ─────────────────────────────────────────────────────
cd src/chat-app/backend
uvicorn app.main:app --reload --port 5000
```

Wait until you see:
```
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:5000
```

```bash
# ── Terminal 2 — Frontend ────────────────────────────────────────────────────
cd src/chat-app/frontend
npm run dev
```

Wait until you see:
```
  VITE v5.x.x  ready in ... ms

  ➜  Local:   http://localhost:3000/
```

VS Code will automatically forward both ports and display notifications.

### Service Health Check

```bash
# Run from any terminal inside the container
curl http://localhost:5000/health
```

**Expected response:**
```json
{"status":"ok"}
```

---

## Scenario 1: Operational State Query (Chat)

- [ ] Open `http://localhost:3000` in a browser
- [ ] The chat interface loads without a console error
- [ ] Select a device from the **device selector** dropdown
  - [ ] The dropdown is populated with device IDs from EventHouse
        (or shows a placeholder if EventHouse is not configured)
- [ ] The **Device State Panel** populates with telemetry data for the selected device
      (or shows *"State unavailable"* if the EventHouse MCP endpoint is not reachable)
- [ ] Type the following message in the chat input:
      > *"What is the current operational state of this device?"*
- [ ] Click **Send** (or press Enter) and observe:
  - [ ] A loading indicator appears while the backend processes the request
  - [ ] A response appears that references device state details from EventHouse
        (or includes a graceful fallback message if EventHouse is not configured)
  - [ ] The conversation ID is displayed or maintained between messages
- [ ] Send a follow-up message to verify context is preserved:
      > *"Is the fan running at full speed?"*
  - [ ] The response acknowledges the previous context (the AI references the same device)

---

## Scenario 2: Device Command — Lamp

- [ ] Ensure a device is selected in the device selector
- [ ] Locate the **Command Panel** in the UI
- [ ] Click **Lamp ON**
  - [ ] A confirmation dialog appears asking you to confirm the action
- [ ] Accept the confirmation
  - [ ] A success message appears: *"Command submitted successfully"*
  - [ ] Backend terminal logs show an EventGrid publish attempt, e.g.:
        ```
        INFO:     Publishing command for device_id=<id> action=lamp
        ```
- [ ] Click **Lamp OFF**
  - [ ] Confirmation dialog appears
  - [ ] Accept confirmation
  - [ ] Success message appears

---

## Scenario 3: Device Command — Fan

- [ ] Ensure a device is selected
- [ ] In the Command Panel, click the **MED (16000)** fan preset
  - [ ] A confirmation dialog appears
- [ ] Accept the confirmation
  - [ ] A success or failure result message appears
        (failure is expected if EventGrid is not configured; verify the error message is
        user-friendly rather than a raw stack trace)
- [ ] Test a custom fan speed:
  - [ ] Enter `8000` in the custom fan speed input field
  - [ ] Click **Set Fan Speed**
  - [ ] Confirmation dialog appears
  - [ ] Accept confirmation
  - [ ] Success or graceful failure message appears

---

## Scenario 4: Error Handling

### Empty Chat Message

- [ ] Clear the chat input field so it is empty
- [ ] Verify the **Send** button is disabled (cannot submit empty message)

### Backend Unavailable

- [ ] Stop the backend process in Terminal 1 (`Ctrl+C`)
- [ ] In the browser, type any message and click **Send**
  - [ ] An **error banner** appears in the UI indicating the backend is unreachable
  - [ ] No unhandled JavaScript exception appears in the browser console
- [ ] Restart the backend:
  ```bash
  cd src/chat-app/backend && uvicorn app.main:app --reload --port 5000
  ```
- [ ] Send another message
  - [ ] The request succeeds (error banner disappears or a new response appears)

### No Device Selected

- [ ] Reload the page or deselect the current device (if the UI supports it)
- [ ] Verify that the **Command Panel** controls (Lamp ON/OFF, Fan presets) are disabled
      or show a message instructing you to select a device first

---

## Backend Unit Tests

Run the full test suite inside the container from the backend directory:

```bash
cd src/chat-app/backend
pytest tests/ -v
```

**Expected result:** All 14 tests pass with no errors.

Sample output:

```
tests/test_cache.py::...          PASSED
tests/test_chat.py::...           PASSED
tests/test_commands.py::...       PASSED
tests/test_device_state.py::...   PASSED
tests/test_health.py::...         PASSED

================== 14 passed in X.XXs ==================
```

If any test fails, inspect the output for missing environment variables or import errors
before continuing with the manual scenarios.

---

## Known Limitations

| Limitation | Notes |
|---|---|
| **Device state requires EventHouse** | If `EVENTHOUSE_MCP_ENDPOINT` is not set or the endpoint is unreachable, all device state queries return `"State unavailable"`. The chat still functions for general queries. |
| **EventGrid publishes require Azure access** | Commands will fail with a service error if `EVENTGRID_MQTT_HOSTNAME` is not set or the identity lacks the **EventGrid Data Sender** role. The UI displays a user-friendly error rather than a raw exception. |
| **Tool-calling path requires Azure OpenAI** | If `AZURE_OPENAI_ENDPOINT` or `AZURE_OPENAI_DEPLOYMENT` is not set, all chat requests will fail at the backend. |
| **Local credential expiry** | `DefaultAzureCredential` falls back to `az login` credentials locally. If the token expires (typically after 1 hour of inactivity), re-run `az login` inside the container. |
| **In-memory conversation state** | Conversation history is stored in memory on the backend process. Restarting the backend resets all conversations. |
| **Fan speed range** | Valid fan speed values are 0–32000 RPM. Values outside this range are rejected by the backend with a 422 error. |

---

## Assumptions

- The EventHouse MCP endpoint follows the `POST {endpoint}/call-tool` request pattern
  documented in `src/chat-app/backend/app/services/eventhouse.py`.
- The EventGrid topic is pre-created in Azure before running the validation.
- The Azure OpenAI model deployment supports function/tool calling (`gpt-4o` is recommended).
- The Vite dev server proxy (`vite.config.js`) targets `http://localhost:5000` — this must
  match the port on which the backend is started.
- All `az role assignment create` commands in `DEPLOYMENT.md §7` have been executed and
  propagated (allow up to 5 minutes) before testing command scenarios.
