"""Server settings, read from environment variables.

Every setting has a safe default so `python -m comb_server serve` works
with no configuration on a laptop.
"""
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    data_dir: Path
    max_record_bytes: int
    max_blob_bytes: int
    pairing_ttl_seconds: int
    claim_attempts_per_window: int
    claim_window_seconds: int
    trust_proxy: bool


def load_settings() -> Settings:
    return Settings(
        data_dir=Path(os.environ.get("COMB_DATA_DIR", "./comb-data")).expanduser().resolve(),
        # One encrypted note or task. 1 MB is far more than any markdown file needs.
        max_record_bytes=int(os.environ.get("COMB_MAX_RECORD_BYTES", str(1024 * 1024))),
        # One encrypted attachment (image, PDF, voice note).
        max_blob_bytes=int(os.environ.get("COMB_MAX_BLOB_MB", "25")) * 1024 * 1024,
        pairing_ttl_seconds=int(os.environ.get("COMB_PAIRING_TTL_SECONDS", "600")),
        claim_attempts_per_window=int(os.environ.get("COMB_CLAIM_ATTEMPTS", "10")),
        claim_window_seconds=int(os.environ.get("COMB_CLAIM_WINDOW_SECONDS", "600")),
        # Set to 1 only when running behind the bundled Caddy proxy, so attempt
        # limits count the real client address instead of the proxy's.
        trust_proxy=os.environ.get("COMB_TRUST_PROXY", "0") == "1",
    )
