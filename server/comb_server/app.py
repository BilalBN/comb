"""Comb sync server.

A blind post office for one person's devices: it stores encrypted records
and attachments, hands them to that person's other devices, and cannot
read any of them. Encryption and decryption happen only on devices.
"""
import base64
import binascii
import hashlib
import logging
import os
import re
from pathlib import Path
from typing import Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, Response, status

from . import __version__
from .config import Settings, load_settings
from .db import Database, now
from .models import (
    BLOB_ID_PATTERN,
    BlobInfo,
    ChangeResult,
    ChangesPage,
    Device,
    DeviceCredentials,
    Health,
    PairingClaim,
    PairingCode,
    PushRequest,
    PushResponse,
    SetupRequest,
    StoredRecord,
)
from .security import AttemptLimiter, digest, new_code, new_id, new_token, normalise_code

log = logging.getLogger("comb")

SETUP_CODE_FILE = "SETUP_CODE.txt"


class Context:
    def __init__(self, account_id: str, device_id: str):
        self.account_id = account_id
        self.device_id = device_id


def issue_setup_code(settings: Settings, db: Database) -> Optional[str]:
    """Create a one-time setup code if no account exists yet.

    The plain code is written to SETUP_CODE.txt in the data folder (readable
    only by the server's user) and printed once in the log. Only its hash
    is stored in the database.
    """
    if db.one("SELECT 1 FROM accounts LIMIT 1"):
        return None
    code = new_code()
    with db.transaction():
        db.execute("UPDATE setup_codes SET used_at = ? WHERE used_at IS NULL", (now(),))
        db.execute(
            "INSERT INTO setup_codes(code_hash, created_at) VALUES (?, ?)",
            (digest(normalise_code(code)), now()),
        )
    path = settings.data_dir / SETUP_CODE_FILE
    path.write_text(code + "\n", encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return code


def create_app(settings: Optional[Settings] = None) -> FastAPI:
    settings = settings or load_settings()
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    blob_root = settings.data_dir / "blobs"
    blob_root.mkdir(exist_ok=True)
    db = Database(settings.data_dir / "comb.sqlite3")
    limiter = AttemptLimiter(settings.claim_attempts_per_window, settings.claim_window_seconds)

    if not db.one("SELECT 1 FROM accounts LIMIT 1") and not db.one(
        "SELECT 1 FROM setup_codes WHERE used_at IS NULL LIMIT 1"
    ):
        code = issue_setup_code(settings, db)
        log.warning("Comb is not set up yet. One-time setup code: %s", code)

    app = FastAPI(
        title="Comb sync server",
        version=__version__,
        description="Stores and forwards end-to-end encrypted records between one person's devices.",
    )
    app.state.settings = settings
    app.state.db = db

    # ---------- helpers ----------

    def client_key(request: Request) -> str:
        if settings.trust_proxy:
            forwarded = request.headers.get("x-forwarded-for", "")
            if forwarded:
                return forwarded.split(",")[0].strip()
        return request.client.host if request.client else "unknown"

    def check_attempts(request: Request) -> None:
        if not limiter.allow(client_key(request)):
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Too many attempts. Wait a few minutes.")

    def register_device(account_id: str, name: str) -> DeviceCredentials:
        device_id = new_id("dev")
        token = new_token()
        db.execute(
            "INSERT INTO devices(id, account_id, name, token_hash, created_at) VALUES (?, ?, ?, ?, ?)",
            (device_id, account_id, name.strip(), digest(token), now()),
        )
        return DeviceCredentials(account_id=account_id, device_id=device_id, token=token)

    def current(authorization: Optional[str] = Header(default=None)) -> Context:
        if not authorization or not authorization.lower().startswith("bearer "):
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sign in with a device token.")
        token = authorization.split(" ", 1)[1].strip()
        row = db.one(
            "SELECT id, account_id FROM devices WHERE token_hash = ? AND revoked_at IS NULL",
            (digest(token),),
        )
        if not row:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "This device is not signed in or was removed.")
        db.execute("UPDATE devices SET last_seen_at = ? WHERE id = ?", (now(), row["id"]))
        return Context(account_id=row["account_id"], device_id=row["id"])

    def to_record(row) -> StoredRecord:
        return StoredRecord(
            record_id=row["id"],
            version=row["version"],
            seq=row["seq"],
            blob=base64.b64encode(row["blob"]).decode("ascii"),
            deleted=bool(row["deleted"]),
            device_id=row["device_id"],
            updated_at=row["updated_at"],
        )

    # ---------- health ----------

    @app.get("/v1/health", response_model=Health, tags=["server"])
    def health() -> Health:
        initialised = bool(db.one("SELECT 1 FROM accounts LIMIT 1"))
        return Health(status="ok", version=__version__, initialised=initialised)

    # ---------- first device ----------

    @app.post("/v1/setup", response_model=DeviceCredentials, tags=["devices"])
    def setup(body: SetupRequest, request: Request) -> DeviceCredentials:
        """Turn the one-time setup code into the first device of a new account."""
        check_attempts(request)
        with db.transaction():
            if db.one("SELECT 1 FROM accounts LIMIT 1"):
                raise HTTPException(status.HTTP_409_CONFLICT, "This server is already set up. Pair a new device instead.")
            row = db.one(
                "SELECT code_hash FROM setup_codes WHERE code_hash = ? AND used_at IS NULL",
                (digest(normalise_code(body.setup_code)),),
            )
            if not row:
                raise HTTPException(status.HTTP_403_FORBIDDEN, "That setup code is not right.")
            db.execute("UPDATE setup_codes SET used_at = ? WHERE code_hash = ?", (now(), row["code_hash"]))
            account_id = new_id("acct")
            db.execute("INSERT INTO accounts(id, created_at) VALUES (?, ?)", (account_id, now()))
            creds = register_device(account_id, body.device_name)
        try:
            (settings.data_dir / SETUP_CODE_FILE).unlink()
        except FileNotFoundError:
            pass
        log.info("Account created with first device %s", creds.device_id)
        return creds

    # ---------- pairing more devices ----------

    @app.post("/v1/pairing", response_model=PairingCode, tags=["devices"])
    def start_pairing(ctx: Context = Depends(current)) -> PairingCode:
        """Create a short-lived, single-use code for adding another device.

        The device that shows the QR code puts this code and the vault key in
        the QR itself. The vault key never touches the server.
        """
        code = new_code()
        expires = now() + settings.pairing_ttl_seconds
        with db.transaction():
            db.execute(
                "INSERT INTO pairings(code_hash, account_id, created_by, expires_at) VALUES (?, ?, ?, ?)",
                (digest(normalise_code(code)), ctx.account_id, ctx.device_id, expires),
            )
        return PairingCode(code=code, expires_at=expires)

    @app.post("/v1/pairing/claim", response_model=DeviceCredentials, tags=["devices"])
    def claim_pairing(body: PairingClaim, request: Request) -> DeviceCredentials:
        check_attempts(request)
        with db.transaction():
            row = db.one(
                "SELECT code_hash, account_id, expires_at FROM pairings WHERE code_hash = ? AND used_at IS NULL",
                (digest(normalise_code(body.code)),),
            )
            if not row or row["expires_at"] < now():
                raise HTTPException(status.HTTP_403_FORBIDDEN, "That pairing code is not right or has expired.")
            db.execute("UPDATE pairings SET used_at = ? WHERE code_hash = ?", (now(), row["code_hash"]))
            return register_device(row["account_id"], body.device_name)

    @app.get("/v1/devices", response_model=list[Device], tags=["devices"])
    def list_devices(ctx: Context = Depends(current)) -> list:
        rows = db.all(
            "SELECT id, name, created_at, last_seen_at, revoked_at FROM devices WHERE account_id = ? ORDER BY created_at",
            (ctx.account_id,),
        )
        return [
            Device(
                id=r["id"],
                name=r["name"],
                created_at=r["created_at"],
                last_seen_at=r["last_seen_at"],
                revoked=r["revoked_at"] is not None,
                this_device=r["id"] == ctx.device_id,
            )
            for r in rows
        ]

    @app.delete("/v1/devices/{device_id}", status_code=204, tags=["devices"])
    def revoke_device(device_id: str, ctx: Context = Depends(current)) -> Response:
        """Sign a lost or old device out. Its token stops working immediately."""
        with db.transaction():
            cur = db.execute(
                "UPDATE devices SET revoked_at = ? WHERE id = ? AND account_id = ? AND revoked_at IS NULL",
                (now(), device_id, ctx.account_id),
            )
            if cur.rowcount == 0:
                raise HTTPException(status.HTTP_404_NOT_FOUND, "No active device with that id.")
        return Response(status_code=204)

    # ---------- records ----------

    @app.post("/v1/records", response_model=PushResponse, tags=["sync"])
    def push(body: PushRequest, ctx: Context = Depends(current)) -> PushResponse:
        """Apply encrypted changes, each guarded by the version it was edited from.

        A change whose base_version no longer matches comes back as a conflict
        with the server's current copy; the device merges and keeps both
        versions rather than losing either. Retrying a change with the same
        change_id returns `duplicate` instead of applying it twice.
        """
        results = []
        with db.transaction():
            for change in body.changes:
                done = db.one(
                    "SELECT record_id, version, seq FROM change_log WHERE account_id = ? AND change_id = ?",
                    (ctx.account_id, change.change_id),
                )
                if done:
                    results.append(
                        ChangeResult(
                            change_id=change.change_id,
                            record_id=done["record_id"],
                            status="duplicate",
                            version=done["version"],
                            seq=done["seq"],
                        )
                    )
                    continue
                try:
                    blob = base64.b64decode(change.blob, validate=True)
                except (binascii.Error, ValueError):
                    raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Change {change.change_id}: blob is not base64.")
                if len(blob) > settings.max_record_bytes:
                    raise HTTPException(
                        413, f"Change {change.change_id}: record is too large."
                    )
                existing = db.one(
                    "SELECT * FROM records WHERE account_id = ? AND id = ?", (ctx.account_id, change.record_id)
                )
                current_version = existing["version"] if existing else 0
                if change.base_version != current_version:
                    results.append(
                        ChangeResult(
                            change_id=change.change_id,
                            record_id=change.record_id,
                            status="conflict",
                            current=to_record(existing) if existing else None,
                        )
                    )
                    continue
                version = current_version + 1
                cur = db.execute(
                    "INSERT INTO change_log(account_id, change_id, record_id, version, created_at) VALUES (?, ?, ?, ?, ?)",
                    (ctx.account_id, change.change_id, change.record_id, version, now()),
                )
                seq = cur.lastrowid
                db.execute(
                    """
                    INSERT INTO records(account_id, id, version, seq, blob, deleted, device_id, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(account_id, id) DO UPDATE SET
                        version = excluded.version, seq = excluded.seq, blob = excluded.blob,
                        deleted = excluded.deleted, device_id = excluded.device_id, updated_at = excluded.updated_at
                    """,
                    (ctx.account_id, change.record_id, version, seq, blob, int(change.deleted), ctx.device_id, now()),
                )
                results.append(
                    ChangeResult(
                        change_id=change.change_id, record_id=change.record_id, status="ok", version=version, seq=seq
                    )
                )
        return PushResponse(results=results)

    @app.get("/v1/changes", response_model=ChangesPage, tags=["sync"])
    def pull(
        since: int = Query(0, ge=0, description="Highest seq this device has already applied."),
        limit: int = Query(200, ge=1, le=1000),
        ctx: Context = Depends(current),
    ) -> ChangesPage:
        rows = db.all(
            "SELECT * FROM records WHERE account_id = ? AND seq > ? ORDER BY seq LIMIT ?",
            (ctx.account_id, since, limit + 1),
        )
        has_more = len(rows) > limit
        rows = rows[:limit]
        next_since = rows[-1]["seq"] if rows else since
        return ChangesPage(changes=[to_record(r) for r in rows], next_since=next_since, has_more=has_more)

    # ---------- attachments ----------

    def blob_path(account_id: str, blob_id: str) -> Path:
        return blob_root / account_id / blob_id[:2] / blob_id

    @app.put("/v1/blobs/{blob_id}", response_model=BlobInfo, tags=["attachments"])
    async def put_blob(blob_id: str, request: Request, ctx: Context = Depends(current)) -> BlobInfo:
        """Store an encrypted attachment. Its id is the SHA-256 of the encrypted bytes."""
        if not re.match(BLOB_ID_PATTERN, blob_id):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Blob id must be a lowercase SHA-256 hex digest.")
        declared = request.headers.get("content-length")
        if declared and int(declared) > settings.max_blob_bytes:
            raise HTTPException(413, "Attachment is too large.")
        hasher = hashlib.sha256()
        chunks = []
        size = 0
        async for chunk in request.stream():
            size += len(chunk)
            if size > settings.max_blob_bytes:
                raise HTTPException(413, "Attachment is too large.")
            hasher.update(chunk)
            chunks.append(chunk)
        if hasher.hexdigest() != blob_id:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Blob id does not match its contents.")
        path = blob_path(ctx.account_id, blob_id)
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            tmp = path.with_suffix(".part")
            tmp.write_bytes(b"".join(chunks))
            tmp.replace(path)
        with db.transaction():
            db.execute(
                "INSERT OR IGNORE INTO blobs(account_id, id, size, created_at) VALUES (?, ?, ?, ?)",
                (ctx.account_id, blob_id, size, now()),
            )
        return BlobInfo(id=blob_id, size=size)

    @app.get("/v1/blobs/{blob_id}", tags=["attachments"])
    def get_blob(blob_id: str, ctx: Context = Depends(current)) -> Response:
        if not re.match(BLOB_ID_PATTERN, blob_id):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "No attachment with that id.")
        row = db.one("SELECT size FROM blobs WHERE account_id = ? AND id = ?", (ctx.account_id, blob_id))
        path = blob_path(ctx.account_id, blob_id)
        if not row or not path.exists():
            raise HTTPException(status.HTTP_404_NOT_FOUND, "No attachment with that id.")
        return Response(content=path.read_bytes(), media_type="application/octet-stream")

    return app
