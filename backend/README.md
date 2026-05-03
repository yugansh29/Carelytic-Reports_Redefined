# Backend hardening notes

This backend now includes:
- Bearer token auth (configurable)
- CORS origin allowlist via env
- Per-IP request rate limiting
- Retry logic for LLM calls
- Production-safe error behavior (no fake clinical responses unless explicitly enabled)

## Environment setup

Copy .env.example to .env and set values.

Key variables:
- APP_ENV: development or production
- REQUIRE_AUTH: true/false
- API_BEARER_TOKEN: required when REQUIRE_AUTH=true
- CORS_ALLOW_ORIGINS: comma-separated list of allowed frontend origins
- RATE_LIMIT_PER_MINUTE: per-IP limit for /api/* except /api/health
- ENABLE_DEMO_FALLBACKS: keep false in production

## Run

Install dependencies and run:

```bash
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```
