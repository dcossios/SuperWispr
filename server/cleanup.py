import re

FILLER_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"\b(uh\s*huh|um+|uh+|hmm+|hm+)\b", re.IGNORECASE),
    re.compile(
        r"(?:^|(?<=\s))(you know|I mean|sort of|kind of|basically|actually|like)"
        r"(?=[,.\s]|$)",
        re.IGNORECASE,
    ),
]

REPEATED_WORD = re.compile(r"\b(\w+)(\s+\1)+\b", re.IGNORECASE)
MULTI_SPACE = re.compile(r"[ \t]+")
CAPITALIZE_AFTER_PERIOD = re.compile(r"(?<=[.!?]\s)([a-z])")
ORPHAN_COMMAS = re.compile(r"\s*,(\s*,)+")
LEADING_COMMA = re.compile(r"^\s*,\s*")
SPACE_BEFORE_PUNCT = re.compile(r"\s+([.,!?;:])")


def cleanup(text: str) -> str:
    """Apply rule-based cleanup to raw Whisper transcription output."""
    if not text or not text.strip():
        return ""

    for pattern in FILLER_PATTERNS:
        text = pattern.sub("", text)

    text = REPEATED_WORD.sub(r"\1", text)

    text = ORPHAN_COMMAS.sub(",", text)
    text = LEADING_COMMA.sub("", text)
    text = SPACE_BEFORE_PUNCT.sub(r"\1", text)

    text = MULTI_SPACE.sub(" ", text).strip()

    text = CAPITALIZE_AFTER_PERIOD.sub(lambda m: m.group(1).upper(), text)

    if text:
        text = text[0].upper() + text[1:]

    return text
