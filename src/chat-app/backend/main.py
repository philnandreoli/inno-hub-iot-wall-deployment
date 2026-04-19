"""Compatibility entrypoint.

Run with: uvicorn main:app --host 0.0.0.0 --port ${PORT:-5000}
"""

from app.main import app
