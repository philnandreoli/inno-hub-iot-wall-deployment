---
applyTo: "src/chat-app/backend/**"
description: "Use when writing or modifying Python backend code — FastAPI routes, services, configuration, validation, or tests."
---
# Backend Python Guidelines

## Patterns

- Use `@dataclass(frozen=True)` for configuration with `@classmethod from_env()` — no Pydantic BaseSettings
- Use FastAPI `Depends()` with `@lru_cache` singletons for dependency injection
- Use `Annotated` type aliases for dependency parameters (e.g., `ClaimsDep`, `PublisherDep`)
- Raise `HTTPException` directly from validators — no custom exception classes
- Use `logger.exception()` in except blocks for full tracebacks

## API Routes

- Routes live in `app/api/routes/` and are registered via `APIRouter` with a prefix
- Map exceptions to HTTP codes: `LookupError` → 404, `RuntimeError`/`OSError` → 502
- Broad except blocks use `# noqa: BLE001` comment
- Return camelCase JSON keys in API responses

## Services

- MQTT publishing uses paho-mqtt v5 with OAuth2 JWT credentials to Azure Event Grid
- Kusto queries use parameterized `declare query_parameters` — never string-interpolate user input into KQL
- Retry logic uses exponential backoff for transient network errors

## Validation

- Standalone validation functions with compiled regex patterns
- Device names must match `^[a-zA-Z0-9-]{1,64}$` and end with `-vm-k3s`

## Testing

- pytest with `TestClient` (synchronous, not async)
- Use fake/stub classes (e.g., `FakePublisher`) instead of mock frameworks
- Override dependencies via `app.dependency_overrides` in a `build_test_client()` helper
- Use `@pytest.mark.parametrize` for input validation tests

## Type Hints

- Use Python 3.11+ union syntax (`str | None`) not `Optional[str]`
- Type-annotate all function signatures
