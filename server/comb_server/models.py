"""Request and response shapes for the sync API (OpenAPI is generated from these)."""
from typing import List, Optional

from pydantic import BaseModel, Field

RECORD_ID_PATTERN = r"^[A-Za-z0-9_-]{16,64}$"
CHANGE_ID_PATTERN = r"^[A-Za-z0-9_-]{16,64}$"
BLOB_ID_PATTERN = r"^[0-9a-f]{64}$"


class Health(BaseModel):
    status: str
    version: str
    initialised: bool


class SetupRequest(BaseModel):
    setup_code: str = Field(min_length=4, max_length=32)
    device_name: str = Field(min_length=1, max_length=64)


class DeviceCredentials(BaseModel):
    account_id: str
    device_id: str
    token: str = Field(description="Bearer token for this device. Shown once; store it securely.")


class Device(BaseModel):
    id: str
    name: str
    created_at: float
    last_seen_at: Optional[float]
    revoked: bool
    this_device: bool


class PairingCode(BaseModel):
    code: str
    expires_at: float


class PairingClaim(BaseModel):
    code: str = Field(min_length=4, max_length=32)
    device_name: str = Field(min_length=1, max_length=64)


class Change(BaseModel):
    change_id: str = Field(pattern=CHANGE_ID_PATTERN, description="Random id chosen by the device; retries reuse it.")
    record_id: str = Field(pattern=RECORD_ID_PATTERN, description="Random id of the record, never a file name.")
    base_version: int = Field(ge=0, description="Version the device edited from; 0 for a new record.")
    blob: str = Field(description="Base64 ciphertext. The server never decrypts it.")
    deleted: bool = False


class PushRequest(BaseModel):
    changes: List[Change] = Field(max_length=500)


class StoredRecord(BaseModel):
    record_id: str
    version: int
    seq: int
    blob: str
    deleted: bool
    device_id: str
    updated_at: float


class ChangeResult(BaseModel):
    change_id: str
    record_id: str
    status: str = Field(description="ok, duplicate (already applied) or conflict")
    version: Optional[int] = None
    seq: Optional[int] = None
    current: Optional[StoredRecord] = Field(
        default=None, description="On conflict: the record as the server has it now, so the device can merge."
    )


class PushResponse(BaseModel):
    results: List[ChangeResult]


class ChangesPage(BaseModel):
    changes: List[StoredRecord]
    next_since: int
    has_more: bool


class BlobInfo(BaseModel):
    id: str
    size: int
