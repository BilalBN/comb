from comb_server.app import SETUP_CODE_FILE


def test_health_before_and_after_setup(client, setup_code):
    assert client.get("/v1/health").json()["initialised"] is False
    client.post("/v1/setup", json={"setup_code": setup_code, "device_name": "Mac"})
    body = client.get("/v1/health").json()
    assert body["status"] == "ok" and body["initialised"] is True


def test_setup_code_is_written_once_and_removed(settings, client, setup_code):
    assert (settings.data_dir / SETUP_CODE_FILE).exists()
    resp = client.post("/v1/setup", json={"setup_code": setup_code, "device_name": "Mac"})
    assert resp.status_code == 200
    assert not (settings.data_dir / SETUP_CODE_FILE).exists()


def test_wrong_setup_code_is_refused(client, setup_code):
    resp = client.post("/v1/setup", json={"setup_code": "WRONG-CODE1", "device_name": "Mac"})
    assert resp.status_code == 403


def test_setup_code_accepts_lowercase_and_no_dash(client, setup_code):
    typed = setup_code.replace("-", "").lower()
    assert client.post("/v1/setup", json={"setup_code": typed, "device_name": "Mac"}).status_code == 200


def test_second_setup_is_refused(client, setup_code):
    client.post("/v1/setup", json={"setup_code": setup_code, "device_name": "Mac"})
    resp = client.post("/v1/setup", json={"setup_code": setup_code, "device_name": "Other"})
    assert resp.status_code == 409


def test_endpoints_need_a_token(client):
    assert client.get("/v1/changes").status_code == 401
    assert client.get("/v1/devices", headers={"Authorization": "Bearer nonsense"}).status_code == 401


def test_pairing_adds_a_device_once(client, first_device):
    headers, _ = first_device
    code = client.post("/v1/pairing", headers=headers).json()["code"]
    phone = client.post("/v1/pairing/claim", json={"code": code, "device_name": "Nothing Phone"})
    assert phone.status_code == 200
    again = client.post("/v1/pairing/claim", json={"code": code, "device_name": "Someone else"})
    assert again.status_code == 403
    names = [d["name"] for d in client.get("/v1/devices", headers=headers).json()]
    assert names == ["MacBook", "Nothing Phone"]


def test_expired_pairing_code_is_refused(make_app, setup_code):
    from fastapi.testclient import TestClient

    app = make_app(pairing_ttl_seconds=-1)
    client = TestClient(app)
    creds = client.post("/v1/setup", json={"setup_code": setup_code, "device_name": "Mac"}).json()
    code = client.post("/v1/pairing", headers={"Authorization": f"Bearer {creds['token']}"}).json()["code"]
    assert client.post("/v1/pairing/claim", json={"code": code, "device_name": "Phone"}).status_code == 403


def test_revoked_device_is_signed_out(client, first_device):
    headers, _ = first_device
    code = client.post("/v1/pairing", headers=headers).json()["code"]
    phone = client.post("/v1/pairing/claim", json={"code": code, "device_name": "Old phone"}).json()
    phone_headers = {"Authorization": f"Bearer {phone['token']}"}
    assert client.get("/v1/changes", headers=phone_headers).status_code == 200
    assert client.delete(f"/v1/devices/{phone['device_id']}", headers=headers).status_code == 204
    assert client.get("/v1/changes", headers=phone_headers).status_code == 401


def test_code_guessing_is_rate_limited(make_app, setup_code):
    from fastapi.testclient import TestClient

    client = TestClient(make_app(claim_attempts_per_window=3))
    statuses = [
        client.post("/v1/pairing/claim", json={"code": "AAAAA-AAAAA", "device_name": "x"}).status_code for _ in range(5)
    ]
    assert statuses[:3] == [403, 403, 403]
    assert statuses[3:] == [429, 429]


def test_tokens_are_stored_hashed(client, first_device, app):
    _, creds = first_device
    stored = [r["token_hash"] for r in app.state.db.all("SELECT token_hash FROM devices")]
    assert creds["token"] not in stored
