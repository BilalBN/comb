# What the Comb server can and cannot see

Comb is end-to-end encrypted. Your devices hold the key; the server never
receives it, not even during pairing (the key travels inside the QR code,
screen to camera).

## The server cannot see

- The text of any note or task, its title, Space, category or priority
- File names and folder structure (records have random ids)
- Attachments (images, PDFs, voice notes)
- Your recovery key

## The server can see (metadata)

- How many devices you have, their names (for example "MacBook") and when
  each was last online
- How many records exist, roughly how large each one is, and when it changed
- Which device made each change
- The network address your devices connect from

## Where data lives

| Place | What it holds | Readable? |
| --- | --- | --- |
| Your devices | The key, the app's local copy, the markdown folder on your computer | Yes, by you |
| Sync server | Encrypted records and attachments, device list | No |
| Backups (Backblaze B2, GitHub) | Copies of the encrypted server data | No |

## If you lose your key

If every device is lost and you no longer have the recovery key saved during
setup, the data cannot be decrypted by anyone. Keep the recovery key
somewhere safe and offline.
