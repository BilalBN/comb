# Comb app

One Flutter codebase for macOS (M1), Android (M2), iOS and Windows (M5).

## Run it on your Mac

You need Flutter (stable) and Xcode.

```bash
cd app
flutter pub get
flutter run -d macos          # a development build with hot reload
flutter build macos --release # a normal app: build/macos/Build/Products/Release/Comb.app
```

The app needs a Comb server. For testing on the Mac, start one from the
repository root with `tools/test-server.sh` and use `http://127.0.0.1:8080`
in the setup wizard.

## Tests

```bash
flutter analyze
flutter test
```

Tests that sync through the real server run when `COMB_SERVER_PYTHON`
points at a Python with the server installed:

```bash
COMB_SERVER_PYTHON=../server/.venv/bin/python flutter test
```

`docs/test-vectors.json` (made by the Python reference client) checks that
the app's encryption gives the same bytes as libsodium.

## Where things are

| Folder | What |
| --- | --- |
| `lib/core/` | Protocol encryption and the server API client |
| `lib/sync/` | Sync engine, encrypted local state, markdown folder mirror |
| `lib/data/` | Spaces, tasks, notes, markdown with frontmatter, quick add, views |
| `lib/security/` | App lock: password, fingerprint, restart detection |
| `lib/app/` | The app controller and this device's preferences |
| `lib/ui/` | Screens and the design tokens (`theme.dart`) |

## Where the app keeps its data on this Mac

`~/Library/Application Support/dev.comb.comb/Comb/`: the encrypted state,
the lock file and preferences. Your notes are readable only through the app
(or in the markdown folder you choose).
