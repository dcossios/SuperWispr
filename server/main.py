"""superWispr transcription server — FastAPI app exposing Whisper over localhost."""

import logging
import tempfile
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, Query, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from .cleanup import cleanup
from .config import AVAILABLE_MODELS, ServerState
from .transcriber import Transcriber

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s — %(message)s",
)
logger = logging.getLogger("superwispr.server")

state = ServerState()
transcriber = Transcriber()


@asynccontextmanager
async def lifespan(app: FastAPI):
    state.is_loading = True
    try:
        transcriber.load_model(state.current_model)
        state.is_loading = False
        logger.info("Server ready with model %s", state.current_model)
    except Exception as exc:
        state.is_loading = False
        state.error = str(exc)
        logger.error("Failed to load model on startup: %s", exc)
    yield
    transcriber.unload()
    logger.info("Server shutting down.")


app = FastAPI(title="superWispr", lifespan=lifespan)


# ── Health ──────────────────────────────────────────────────────────────────


@app.get("/health")
async def health():
    return {
        "status": "ok" if transcriber.is_loaded else "error",
        "model": transcriber.model_name,
        "is_loading": state.is_loading,
        "error": state.error,
    }


# ── Transcribe ──────────────────────────────────────────────────────────────


@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    language: str = Query(default="auto"),
    do_cleanup: bool = Query(default=True, alias="cleanup"),
):
    if not transcriber.is_loaded:
        return JSONResponse(
            status_code=503,
            content={"error": "Model not loaded yet. Try again shortly."},
        )

    suffix = Path(file.filename or "audio.wav").suffix or ".wav"
    tmp = tempfile.NamedTemporaryFile(suffix=suffix, delete=False)
    try:
        tmp.write(await file.read())
        tmp.flush()
        tmp.close()

        raw_text = transcriber.transcribe(
            tmp.name,
            language=language if language != "auto" else None,
        )

        cleaned = cleanup(raw_text) if do_cleanup else raw_text

        return {
            "text": cleaned,
            "raw": raw_text,
            "model": transcriber.model_name,
            "language": language,
        }
    except Exception as exc:
        logger.exception("Transcription failed")
        return JSONResponse(status_code=500, content={"error": str(exc)})
    finally:
        Path(tmp.name).unlink(missing_ok=True)


# ── Config (hot-swap model) ─────────────────────────────────────────────────


class ConfigUpdate(BaseModel):
    model: str | None = None


@app.post("/config")
async def update_config(body: ConfigUpdate):
    if body.model:
        if body.model not in AVAILABLE_MODELS:
            return JSONResponse(
                status_code=400,
                content={
                    "error": f"Unknown model. Available: {AVAILABLE_MODELS}",
                },
            )
        state.is_loading = True
        state.error = None
        try:
            transcriber.load_model(body.model)
            state.current_model = body.model
            state.is_loading = False
            return {"status": "ok", "model": body.model}
        except Exception as exc:
            state.is_loading = False
            state.error = str(exc)
            logger.exception("Failed to swap model")
            return JSONResponse(status_code=500, content={"error": str(exc)})

    return {"status": "no_change", "model": state.current_model}


# ── Entrypoint (for `python -m server.main`) ────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    from .config import HOST, PORT

    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
