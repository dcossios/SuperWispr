"""Allow running the server with `python -m server`."""

import uvicorn

from .config import HOST, PORT
from .main import app

uvicorn.run(app, host=HOST, port=PORT, log_level="info")
