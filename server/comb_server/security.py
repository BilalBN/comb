"""Tokens, one-time codes and attempt limiting.

Only hashes of tokens and codes are stored, so a copy of the database
cannot be used to sign in as a device.
"""
import hashlib
import hmac
import secrets
import threading
import time
from collections import defaultdict, deque

# No 0/O, 1/I/L: codes are read off a screen and typed by people.
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def new_id(prefix: str) -> str:
    return f"{prefix}_{secrets.token_hex(8)}"


def new_token() -> str:
    return secrets.token_urlsafe(32)


def new_code(length: int = 10) -> str:
    raw = "".join(secrets.choice(CODE_ALPHABET) for _ in range(length))
    return f"{raw[:5]}-{raw[5:]}" if length == 10 else raw


def normalise_code(code: str) -> str:
    return "".join(ch for ch in code.upper() if ch in CODE_ALPHABET)


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def same(a: str, b: str) -> bool:
    return hmac.compare_digest(a, b)


class AttemptLimiter:
    """Counts attempts per key (client address) in a sliding window.

    Guards the two endpoints that accept a code without a device token,
    so codes cannot be guessed by brute force.
    """

    def __init__(self, limit: int, window_seconds: int):
        self.limit = limit
        self.window = window_seconds
        self._hits = defaultdict(deque)
        self._lock = threading.Lock()

    def allow(self, key: str) -> bool:
        cutoff = time.monotonic() - self.window
        with self._lock:
            hits = self._hits[key]
            while hits and hits[0] < cutoff:
                hits.popleft()
            if len(hits) >= self.limit:
                return False
            hits.append(time.monotonic())
            if len(self._hits) > 10_000:
                for stale in [k for k, v in self._hits.items() if not v or v[-1] < cutoff]:
                    del self._hits[stale]
            return True
