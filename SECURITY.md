# Security

## Reporting a problem

Please do not open a public issue for a security problem. Use GitHub's
"Report a vulnerability" (Security tab → Advisories) on this repository.

## Design summary

- **Encryption:** XChaCha20-Poly1305 (libsodium) with a 256-bit vault key
  generated on the first device. Separate subkeys for records and
  attachments, derived with keyed BLAKE2b. Each record's ciphertext is bound
  to its record id, so the server cannot swap or replay records unnoticed.
- **Device sign-in:** each device gets a random 256-bit token at setup or
  pairing. The server stores only SHA-256 hashes of tokens and codes.
- **Codes:** the one-time setup code and pairing codes are 10 characters
  (about 50 bits), single use; pairing codes expire after 10 minutes. Both
  endpoints are rate limited per client address.
- **Lost device:** remove it from the device list; its token stops working
  immediately.
- **Transport:** in production the server runs behind Caddy with automatic
  HTTPS; only ports 80 and 443 (and SSH) are open.

Full details are in [docs/protocol.md](docs/protocol.md).

## Known limits

- Metadata (record count, sizes, timing, device names) is visible to the
  server; see [PRIVACY.md](PRIVACY.md).
- A revoked device that still has the vault key could read any old data it
  had already downloaded. Rotating the vault key is planned for a later
  milestone.
