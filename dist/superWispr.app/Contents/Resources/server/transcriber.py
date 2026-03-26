import logging
import time
from pathlib import Path

import torch
from transformers import pipeline

from .config import BATCH_SIZE, DEFAULT_MODEL

logger = logging.getLogger("superwispr.transcriber")


class Transcriber:
    """Manages a Whisper ASR pipeline, keeping the model warm in memory."""

    def __init__(self) -> None:
        self._pipe: pipeline | None = None
        self._model_name: str | None = None

    @property
    def model_name(self) -> str | None:
        return self._model_name

    @property
    def is_loaded(self) -> bool:
        return self._pipe is not None

    def load_model(self, model_name: str = DEFAULT_MODEL) -> None:
        if self._model_name == model_name and self._pipe is not None:
            logger.info("Model %s already loaded, skipping.", model_name)
            return

        logger.info("Loading model %s …", model_name)
        start = time.monotonic()

        device = "mps" if torch.backends.mps.is_available() else "cpu"
        dtype = torch.float16 if device == "mps" else torch.float32

        self._pipe = pipeline(
            "automatic-speech-recognition",
            model=model_name,
            dtype=dtype,
            device=device,
            model_kwargs={"attn_implementation": "sdpa"},
        )

        self._model_name = model_name
        elapsed = time.monotonic() - start
        logger.info("Model loaded in %.1fs on device=%s", elapsed, device)

    def transcribe(
        self,
        audio_path: str | Path,
        language: str | None = None,
    ) -> str:
        if self._pipe is None:
            raise RuntimeError("No model loaded. Call load_model() first.")

        generate_kwargs: dict = {}
        if language and language != "auto":
            generate_kwargs["language"] = language

        start = time.monotonic()

        result = self._pipe(
            str(audio_path),
            chunk_length_s=30,
            batch_size=BATCH_SIZE,
            return_timestamps=True,
            generate_kwargs=generate_kwargs,
        )

        elapsed = time.monotonic() - start
        text = result.get("text", "").strip() if isinstance(result, dict) else ""
        logger.info("Transcribed in %.2fs (%d chars)", elapsed, len(text))
        return text

    def unload(self) -> None:
        self._pipe = None
        self._model_name = None
        if torch.backends.mps.is_available():
            torch.mps.empty_cache()
        logger.info("Model unloaded.")
