"""SQLite storage for the sync server.

The server stores only what it needs to route encrypted data between a
person's devices. Record contents are opaque ciphertext; record ids are
random strings chosen by clients, so file names never reach the server.
"""
import sqlite3
import threading
import time
from pathlib import Path

SCHEMA_VERSION = 1

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- One row per person. v1 runs one account per server; the column exists
-- everywhere so family accounts can be added without a migration of data.
CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY,
    created_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS setup_codes (
    code_hash TEXT PRIMARY KEY,
    created_at REAL NOT NULL,
    used_at REAL
);

CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES accounts(id),
    name TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    created_at REAL NOT NULL,
    last_seen_at REAL,
    revoked_at REAL
);

CREATE TABLE IF NOT EXISTS pairings (
    code_hash TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES accounts(id),
    created_by TEXT NOT NULL REFERENCES devices(id),
    expires_at REAL NOT NULL,
    used_at REAL
);

-- Latest state of each encrypted record. `seq` is the change-feed position
-- of the most recent write, so a device that last saw seq N asks for > N.
CREATE TABLE IF NOT EXISTS records (
    account_id TEXT NOT NULL REFERENCES accounts(id),
    id TEXT NOT NULL,
    version INTEGER NOT NULL,
    seq INTEGER NOT NULL,
    blob BLOB NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0,
    device_id TEXT NOT NULL,
    updated_at REAL NOT NULL,
    PRIMARY KEY (account_id, id)
);
CREATE INDEX IF NOT EXISTS records_by_seq ON records(account_id, seq);

-- Every accepted change, so an offline device retrying its outbox gets the
-- same answer twice instead of creating a duplicate.
CREATE TABLE IF NOT EXISTS change_log (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id TEXT NOT NULL,
    change_id TEXT NOT NULL,
    record_id TEXT NOT NULL,
    version INTEGER NOT NULL,
    created_at REAL NOT NULL,
    UNIQUE (account_id, change_id)
);

CREATE TABLE IF NOT EXISTS blobs (
    account_id TEXT NOT NULL REFERENCES accounts(id),
    id TEXT NOT NULL,
    size INTEGER NOT NULL,
    created_at REAL NOT NULL,
    PRIMARY KEY (account_id, id)
);
"""


class Database:
    """A small wrapper that serialises writes behind one lock.

    SQLite in WAL mode handles concurrent readers well; a single write lock
    keeps version checks and sequence numbers consistent without needing
    anything heavier for a personal server.
    """

    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        self._conn = sqlite3.connect(str(path), check_same_thread=False, isolation_level=None)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._conn.execute("PRAGMA busy_timeout=5000")
        self.lock = threading.RLock()
        with self.lock:
            self._conn.executescript(SCHEMA)
            self._conn.execute(
                "INSERT OR IGNORE INTO meta(key, value) VALUES ('schema_version', ?)",
                (str(SCHEMA_VERSION),),
            )

    # Every call takes the lock: the connection is shared between request
    # threads, and a read must never run inside another thread's transaction.
    def execute(self, sql: str, params: tuple = ()) -> sqlite3.Cursor:
        with self.lock:
            return self._conn.execute(sql, params)

    def one(self, sql: str, params: tuple = ()):
        with self.lock:
            return self._conn.execute(sql, params).fetchone()

    def all(self, sql: str, params: tuple = ()):
        with self.lock:
            return self._conn.execute(sql, params).fetchall()

    def transaction(self):
        return _Transaction(self)

    def close(self) -> None:
        self._conn.close()


class _Transaction:
    def __init__(self, db: Database):
        self.db = db

    def __enter__(self):
        self.db.lock.acquire()
        self.db._conn.execute("BEGIN IMMEDIATE")
        return self.db

    def __exit__(self, exc_type, exc, tb):
        try:
            if exc_type is None:
                self.db._conn.execute("COMMIT")
            else:
                self.db._conn.execute("ROLLBACK")
        finally:
            self.db.lock.release()
        return False


def now() -> float:
    return time.time()
