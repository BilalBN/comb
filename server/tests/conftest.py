import sys
from dataclasses import replace
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "refclient"))

from comb_server.app import SETUP_CODE_FILE, create_app  # noqa: E402
from comb_server.config import load_settings  # noqa: E402


@pytest.fixture
def settings(tmp_path, monkeypatch):
    monkeypatch.setenv("COMB_DATA_DIR", str(tmp_path / "data"))
    return load_settings()


@pytest.fixture
def make_app(settings):
    apps = []

    def _make(**overrides):
        app = create_app(replace(settings, **overrides))
        apps.append(app)
        return app

    yield _make
    for app in apps:
        app.state.db.close()


@pytest.fixture
def app(make_app):
    return make_app()


@pytest.fixture
def client(app):
    return TestClient(app)


@pytest.fixture
def setup_code(settings, app):
    return (settings.data_dir / SETUP_CODE_FILE).read_text().strip()


@pytest.fixture
def first_device(client, setup_code):
    creds = client.post("/v1/setup", json={"setup_code": setup_code, "device_name": "MacBook"}).json()
    return {"Authorization": f"Bearer {creds['token']}"}, creds
