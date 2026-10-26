"""Reference Comb client in Python.

This is the executable version of docs/protocol.md. The Flutter apps
implement the same steps in Dart; the server tests use this client to
prove the whole loop works and that the server only ever sees ciphertext.

Crypto (libsodium via PyNaCl, the same primitives the Dart apps use):
- vault key: 32 random bytes, generated on the first device, never sent to the server
- subkeys:   BLAKE2b-256 keyed by the vault key, personalised per purpose
- records:   XChaCha20-Poly1305 (IETF), 24-byte random nonce,
             additional data binds the ciphertext to its record id
- blobs:     same cipher with the attachment subkey; blob id = SHA-256 of ciphertext
"""
import base64
import hashlib
import json
import secrets
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, List, Optional
from urllib.parse import parse_qs, quote, urlparse

from nacl import bindings
from nacl.hash import blake2b
from nacl.encoding import RawEncoder

FORMAT_V1 = b"\x01"
KEYCHECK_RECORD_ID = "0000keycheck0000"
KEYCHECK_PLAINTEXT = {"type": "keycheck", "value": "comb-keycheck-v1"}


class DecryptError(Exception):
    """The key is wrong or the data was changed after it was encrypted."""


# ---------------------------------------------------------------- keys


@dataclass(frozen=True)
class VaultKey:
    raw: bytes

    @staticmethod
    def generate() -> "VaultKey":
        return VaultKey(secrets.token_bytes(32))

    def subkey(self, purpose: bytes) -> bytes:
        person = purpose.ljust(16, b"\0")[:16]
        return blake2b(b"", digest_size=32, key=self.raw, person=person, encoder=RawEncoder)

    @property
    def record_key(self) -> bytes:
        return self.subkey(b"comb-record-v1")

    @property
    def blob_key(self) -> bytes:
        return self.subkey(b"comb-blob-v1")

    def recovery_key(self) -> str:
        """Human-copyable form: base32 of key + 2-byte checksum, in groups of five."""
        check = blake2b(self.raw, digest_size=2, encoder=RawEncoder)
        text = base64.b32encode(self.raw + check).decode("ascii").rstrip("=")
        return "-".join(text[i : i + 5] for i in range(0, len(text), 5))

    @staticmethod
    def from_recovery_key(text: str) -> "VaultKey":
        cleaned = "".join(ch for ch in text.upper() if ch.isalnum())
        padded = cleaned + "=" * (-len(cleaned) % 8)
        try:
            data = base64.b32decode(padded)
        except Exception as exc:  # noqa: BLE001
            raise ValueError("That recovery key is not valid.") from exc
        raw, check = data[:32], data[32:]
        if len(raw) != 32 or blake2b(raw, digest_size=2, encoder=RawEncoder) != check:
            raise ValueError("That recovery key has a typo.")
        return VaultKey(raw)


def new_record_id() -> str:
    """Random, so the server learns nothing from ids (never a file name)."""
    return base64.urlsafe_b64encode(secrets.token_bytes(16)).decode("ascii").rstrip("=")


def new_change_id() -> str:
    return base64.urlsafe_b64encode(secrets.token_bytes(16)).decode("ascii").rstrip("=")


# ---------------------------------------------------------------- sealing


def _aad(kind: bytes, ident: str) -> bytes:
    return b"comb:" + kind + b":" + ident.encode("ascii")


def seal_record(key: VaultKey, record_id: str, payload: dict) -> bytes:
    nonce = secrets.token_bytes(24)
    plaintext = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    ct = bindings.crypto_aead_xchacha20poly1305_ietf_encrypt(plaintext, _aad(b"record", record_id), nonce, key.record_key)
    return FORMAT_V1 + nonce + ct


def open_record(key: VaultKey, record_id: str, blob: bytes) -> dict:
    if len(blob) < 1 + 24 + 16 or blob[:1] != FORMAT_V1:
        raise DecryptError("Unknown record format.")
    nonce, ct = blob[1:25], blob[25:]
    try:
        plaintext = bindings.crypto_aead_xchacha20poly1305_ietf_decrypt(ct, _aad(b"record", record_id), nonce, key.record_key)
    except Exception as exc:  # noqa: BLE001
        raise DecryptError("Could not decrypt this record.") from exc
    return json.loads(plaintext.decode("utf-8"))


def seal_blob(key: VaultKey, data: bytes) -> tuple:
    """Returns (blob_id, ciphertext). The id is the SHA-256 of the ciphertext."""
    nonce = secrets.token_bytes(24)
    ct = FORMAT_V1 + nonce + bindings.crypto_aead_xchacha20poly1305_ietf_encrypt(data, _aad(b"blob", "v1"), nonce, key.blob_key)
    return hashlib.sha256(ct).hexdigest(), ct


def open_blob(key: VaultKey, ct: bytes) -> bytes:
    if len(ct) < 1 + 24 + 16 or ct[:1] != FORMAT_V1:
        raise DecryptError("Unknown attachment format.")
    try:
        return bindings.crypto_aead_xchacha20poly1305_ietf_decrypt(ct[25:], _aad(b"blob", "v1"), ct[1:25], key.blob_key)
    except Exception as exc:  # noqa: BLE001
        raise DecryptError("Could not decrypt this attachment.") from exc


# ---------------------------------------------------------------- pairing QR


def pairing_link(server_url: str, code: str, key: VaultKey) -> str:
    """What the QR code on an existing device holds. The key never goes to the server."""
    return f"comb://pair?server={quote(server_url, safe='')}&code={quote(code)}&key={quote(key.recovery_key())}"


def parse_pairing_link(link: str) -> tuple:
    parsed = urlparse(link)
    if parsed.scheme != "comb" or parsed.netloc != "pair":
        raise ValueError("Not a Comb pairing link.")
    q = parse_qs(parsed.query)
    return q["server"][0], q["code"][0], VaultKey.from_recovery_key(q["key"][0])


# ---------------------------------------------------------------- client


Transport = Callable[..., object]  # httpx.Client or FastAPI TestClient


@dataclass
class Device:
    """One device's view: its credentials, its key, and the files it knows."""

    http: object
    key: VaultKey
    name: str
    token: Optional[str] = None
    device_id: Optional[str] = None
    since: int = 0
    # record_id -> (version, path); path -> record_id
    known: Dict[str, tuple] = field(default_factory=dict)
    by_path: Dict[str, str] = field(default_factory=dict)
    outbox: List[dict] = field(default_factory=list)

    def _headers(self) -> dict:
        return {"Authorization": f"Bearer {self.token}"}

    def _check(self, resp):
        if resp.status_code >= 400:
            raise RuntimeError(f"{resp.status_code}: {resp.text}")
        return resp

    # --- joining

    def setup(self, setup_code: str) -> None:
        creds = self._check(self.http.post("/v1/setup", json={"setup_code": setup_code, "device_name": self.name})).json()
        self.token, self.device_id = creds["token"], creds["device_id"]
        self.queue_payload(KEYCHECK_RECORD_ID, KEYCHECK_PLAINTEXT, path=None)
        self.sync()

    def start_pairing(self, server_url: str) -> str:
        code = self._check(self.http.post("/v1/pairing", headers=self._headers())).json()["code"]
        return pairing_link(server_url, code, self.key)

    @staticmethod
    def join(http, link: str, name: str) -> "Device":
        _, code, key = parse_pairing_link(link)
        device = Device(http=http, key=key, name=name)
        creds = device._check(http.post("/v1/pairing/claim", json={"code": code, "device_name": name})).json()
        device.token, device.device_id = creds["token"], creds["device_id"]
        return device

    # --- local edits

    def queue_payload(self, record_id: str, payload: dict, path: Optional[str], deleted: bool = False) -> None:
        base = self.known.get(record_id, (0, None))[0]
        self.outbox.append(
            {
                "change_id": new_change_id(),
                "record_id": record_id,
                "base_version": base,
                "blob": base64.b64encode(seal_record(self.key, record_id, payload)).decode("ascii"),
                "deleted": deleted,
                "_path": path,
            }
        )

    def write_file(self, path: str, content: str) -> str:
        record_id = self.by_path.get(path) or new_record_id()
        self.by_path[path] = record_id
        self.queue_payload(record_id, {"type": "file", "path": path, "content": content}, path)
        return record_id

    def delete_file(self, path: str) -> None:
        record_id = self.by_path[path]
        self.queue_payload(record_id, {"type": "deleted", "path": path}, path, deleted=True)

    # --- sync

    def push(self) -> List[dict]:
        if not self.outbox:
            return []
        body = {"changes": [{k: v for k, v in c.items() if not k.startswith("_")} for c in self.outbox]}
        results = self._check(self.http.post("/v1/records", json=body, headers=self._headers())).json()["results"]
        conflicts = []
        for change, result in zip(self.outbox, results):
            if result["status"] in ("ok", "duplicate"):
                self.known[change["record_id"]] = (result["version"], change["_path"])
            else:
                conflicts.append(result)
        self.outbox = []
        return conflicts

    def pull(self, folder: Optional[Path] = None) -> List[dict]:
        applied = []
        while True:
            page = self._check(
                self.http.get("/v1/changes", params={"since": self.since}, headers=self._headers())
            ).json()
            for rec in page["changes"]:
                payload = open_record(self.key, rec["record_id"], base64.b64decode(rec["blob"]))
                path = payload.get("path")
                self.known[rec["record_id"]] = (rec["version"], path)
                if path:
                    self.by_path[path] = rec["record_id"]
                    if folder is not None:
                        target = folder / path
                        if rec["deleted"]:
                            target.unlink(missing_ok=True)
                        else:
                            target.parent.mkdir(parents=True, exist_ok=True)
                            tmp = target.with_name(target.name + ".comb-tmp")
                            tmp.write_text(payload["content"], encoding="utf-8")
                            tmp.replace(target)
                applied.append(payload)
            self.since = page["next_since"]
            if not page["has_more"]:
                return applied

    def sync(self, folder: Optional[Path] = None) -> List[dict]:
        conflicts = self.push()
        self.pull(folder)
        return conflicts

    def verify_key(self) -> bool:
        """A newly paired device confirms its key opens the keycheck record."""
        page = self._check(self.http.get("/v1/changes", params={"since": 0, "limit": 1000}, headers=self._headers())).json()
        for rec in page["changes"]:
            if rec["record_id"] == KEYCHECK_RECORD_ID:
                try:
                    return open_record(self.key, rec["record_id"], base64.b64decode(rec["blob"])) == KEYCHECK_PLAINTEXT
                except DecryptError:
                    return False
        return False
