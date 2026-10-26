"""The committed API contract (docs/openapi.json) must match the server.

The Flutter app's client is generated from that file, so a server change
that forgets to update it would silently break the apps. If this fails,
run:  python -m comb_server openapi ../docs/openapi.json
"""
import json
from pathlib import Path

CONTRACT = Path(__file__).resolve().parents[2] / "docs" / "openapi.json"


def test_contract_is_up_to_date(app):
    committed = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert committed == app.openapi(), "docs/openapi.json is out of date; regenerate it"
