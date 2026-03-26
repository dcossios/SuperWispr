from dataclasses import dataclass, field

DEFAULT_MODEL = "openai/whisper-large-v3-turbo"
AVAILABLE_MODELS = [
    "openai/whisper-large-v3-turbo",
    "openai/whisper-large-v3",
    "distil-whisper/distil-large-v3",
]

HOST = "127.0.0.1"
PORT = 9876
BATCH_SIZE = 4


@dataclass
class ServerState:
    current_model: str = DEFAULT_MODEL
    language: str | None = None
    cleanup_enabled: bool = True
    is_loading: bool = False
    error: str | None = None
