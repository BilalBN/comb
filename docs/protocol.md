# Comb sync protocol, version 1

This is the contract between Comb devices and the sync server. The Python
reference client in `tools/refclient/comb_ref.py` implements every step and
is exercised by the server tests; the Flutter apps implement the same steps
in Dart.

## 1. Keys

| Key | How it is made | Where it lives |
| --- | --- | --- |
| Vault key | 32 random bytes, on the first device | Devices only (secure storage) |
| Record key | BLAKE2b-256, keyed by vault key, personalisation `comb-record-v1` (padded to 16 bytes with zeros), empty message | Derived on demand |
| Blob key | Same, personalisation `comb-blob-v1` | Derived on demand |

**Recovery key** = base32 (RFC 4648, no padding) of `vault key ‖ BLAKE2b-16bit(vault key)`,
split into groups of five with dashes. The 2-byte checksum catches typos.
Shown once during setup; the person saves it offline.

## 2. Records

A record is one file (a note, a task, a daily note) or a settings item.

- **Record id:** 16 random bytes, base64url without padding (22 characters).
  Never derived from the file name, so the server learns nothing from ids.
- **Plaintext:** compact JSON, keys sorted. For files:
  `{"type":"file","path":"Tasks/Call GCD.md","content":"---\n…"}`.
  A delete is `{"type":"deleted","path":"…"}` sent with `deleted: true`.
- **Ciphertext ("blob"):** `0x01 ‖ nonce(24) ‖ XChaCha20-Poly1305-IETF(record key, nonce, plaintext, AD)`
  with additional data `comb:record:<record id>` (ASCII). Binding the id
  means a server that swaps two records' blobs is detected on decrypt.
- **Keycheck record:** id `0000keycheck0000`, plaintext
  `{"type":"keycheck","value":"comb-keycheck-v1"}`. Written by the first
  device; a newly paired device decrypts it to confirm it has the right key.

## 3. Attachments

`blob = 0x01 ‖ nonce(24) ‖ XChaCha20-Poly1305-IETF(blob key, nonce, bytes, AD "comb:blob:v1")`.
Its id is the lowercase SHA-256 hex of the blob. The server checks the hash
on upload. A record references an attachment by this id.

## 4. Joining

1. **First device.** The server prints a one-time setup code on first start
   (also in `comb-data/SETUP_CODE.txt`). The device calls `POST /v1/setup`
   with it, receives a device token, generates the vault key, shows the
   recovery key, and writes the keycheck record.
2. **More devices.** An existing device calls `POST /v1/pairing` and gets a
   code valid for 10 minutes. It shows a QR code containing
   `comb://pair?server=<url>&code=<code>&key=<recovery key>`.
   The new device scans it, calls `POST /v1/pairing/claim` with the code,
   receives its own token, and checks the keycheck record. The key goes
   camera to screen; it is never sent to the server.

All other calls carry `Authorization: Bearer <device token>`.

## 5. Sync

**Push** (`POST /v1/records`): a batch of up to 500 changes, each with

- `change_id`: random, chosen when the edit is made and kept in the
  device's outbox, so a retry after a dropped connection returns
  `duplicate` instead of applying twice;
- `record_id`, `blob`, `deleted`;
- `base_version`: the version the device edited from (0 for new).

Per change the server answers `ok` (with the new `version` and `seq`),
`duplicate`, or `conflict` (with the server's `current` copy). The whole
batch is rejected if any blob is malformed or too large.

**Conflicts.** The device never discards either side. It keeps the
server's version under the original name and saves its own as
`<name> (conflict <device> <date>).md`, then pushes both.

**Pull** (`GET /v1/changes?since=<seq>`): records whose latest change is
after `seq`, oldest first, in pages. The device applies each one, writes
files atomically (temporary file, then rename), and remembers `next_since`.

## 6. Limits

| Item | Default | Setting |
| --- | --- | --- |
| Record size | 1 MB | `COMB_MAX_RECORD_BYTES` |
| Attachment size | 25 MB | `COMB_MAX_BLOB_MB` |
| Pairing code lifetime | 10 minutes | `COMB_PAIRING_TTL_SECONDS` |
| Code attempts | 10 per 10 minutes per address | `COMB_CLAIM_ATTEMPTS`, `COMB_CLAIM_WINDOW_SECONDS` |

## 7. Versioning

Blobs start with a format byte (`0x01`). A future format adds a new byte;
devices keep reading old ones.
