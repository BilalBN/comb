# Comb

Comb is a private notes and tasks app for work, personal life and your own
business, in one place. It runs on your phone and computer, keeps everything
as plain markdown files you own, and syncs through a small server that only
ever sees encrypted data.

- **End-to-end encrypted.** Notes, tasks and attachments are encrypted on
  your devices. The sync server stores and forwards them but cannot read them.
- **Plain files.** Your computer keeps a normal folder of markdown files.
  Open it in Obsidian (optional) and the graph view works out of the box.
- **Yours to shape.** Spaces (Personal, your company, your side business),
  categories, priorities, a Matrix view (urgent × important), themes.
- **Open source, every feature free.**

> Status: early development. Milestone M0 (the encrypted sync server) is in
> this repository; the Flutter apps arrive next. See the roadmap below.

## How it fits together

```
 phone app ──┐                         ┌── Mac / Windows app ── markdown folder ── Obsidian (optional)
             ├──  Comb sync server  ───┤
 email in ───┘   (stores ciphertext)   └── encrypted backups (Backblaze B2, GitHub)
```

The server can run on a small cloud machine (for example a DigitalOcean
droplet) or a computer at home. Either way it only holds encrypted data.

## Repository layout

| Folder | What lives there |
| --- | --- |
| `server/` | The sync server (Python, FastAPI, SQLite) and its tests |
| `tools/refclient/` | Reference client in Python: the protocol as runnable code, used by the tests |
| `app/` | Flutter apps for Android, iOS, macOS and Windows (from M1) |
| `docs/` | Protocol, API contract (`openapi.json`) |
| `deploy/` | Running the server on a droplet with HTTPS |

## Run the server on your computer

You need Python 3.10 or newer.

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
python -m pytest                   # all tests should pass
python -m comb_server serve        # http://127.0.0.1:8080/v1/health
```

The first start prints a one-time **setup code** and saves it to
`comb-data/SETUP_CODE.txt`. The first app you connect uses it; every later
device is added by scanning a QR code from a device you already have.

## Roadmap

| Milestone | What it delivers |
| --- | --- |
| M0 | Encrypted sync server, device pairing, protocol, CI |
| M1 | Mac app: setup, Spaces, tasks, notes, Matrix view, markdown folder, backups |
| M2 | Android app: share-to-task from WhatsApp, offline capture, widgets, reminders |
| M3 | Email to task, digests, calendar per Space |
| M4 | iOS app and widget, Windows app |
| M5 | Public release, then family accounts on one server |

## Contributing

Work happens on feature branches and reaches `main` only after it is tested.
See [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: [SECURITY.md](SECURITY.md).
What the server can and cannot see: [PRIVACY.md](PRIVACY.md).

## License

MIT, see [LICENSE](LICENSE).
