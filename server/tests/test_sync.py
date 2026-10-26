import base64
import hashlib
import secrets


def rid():
    return base64.urlsafe_b64encode(secrets.token_bytes(16)).decode().rstrip("=")


def change(record_id, base=0, blob=b"\x01opaque", deleted=False, change_id=None):
    return {
        "change_id": change_id or rid(),
        "record_id": record_id,
        "base_version": base,
        "blob": base64.b64encode(blob).decode(),
        "deleted": deleted,
    }


def test_create_update_and_feed(client, first_device):
    headers, _ = first_device
    r = rid()
    first = client.post("/v1/records", json={"changes": [change(r)]}, headers=headers).json()["results"][0]
    assert first["status"] == "ok" and first["version"] == 1
    second = client.post("/v1/records", json={"changes": [change(r, base=1, blob=b"\x01v2")]}, headers=headers).json()
    assert second["results"][0]["version"] == 2
    feed = client.get("/v1/changes", params={"since": 0}, headers=headers).json()
    assert [c["version"] for c in feed["changes"]] == [2]
    assert base64.b64decode(feed["changes"][0]["blob"]) == b"\x01v2"


def test_stale_edit_comes_back_as_conflict_with_current_copy(client, first_device):
    headers, _ = first_device
    r = rid()
    client.post("/v1/records", json={"changes": [change(r)]}, headers=headers)
    client.post("/v1/records", json={"changes": [change(r, base=1, blob=b"\x01from-mac")]}, headers=headers)
    stale = client.post("/v1/records", json={"changes": [change(r, base=1, blob=b"\x01from-phone")]}, headers=headers)
    result = stale.json()["results"][0]
    assert result["status"] == "conflict"
    assert base64.b64decode(result["current"]["blob"]) == b"\x01from-mac"


def test_retrying_the_same_change_is_not_applied_twice(client, first_device):
    headers, _ = first_device
    c = change(rid())
    a = client.post("/v1/records", json={"changes": [c]}, headers=headers).json()["results"][0]
    b = client.post("/v1/records", json={"changes": [c]}, headers=headers).json()["results"][0]
    assert a["status"] == "ok" and b["status"] == "duplicate"
    assert a["seq"] == b["seq"] and a["version"] == b["version"] == 1


def test_delete_leaves_a_tombstone(client, first_device):
    headers, _ = first_device
    r = rid()
    client.post("/v1/records", json={"changes": [change(r)]}, headers=headers)
    client.post("/v1/records", json={"changes": [change(r, base=1, deleted=True)]}, headers=headers)
    feed = client.get("/v1/changes", headers=headers).json()["changes"]
    assert feed[0]["deleted"] is True and feed[0]["version"] == 2


def test_feed_pages(client, first_device):
    headers, _ = first_device
    client.post("/v1/records", json={"changes": [change(rid()) for _ in range(5)]}, headers=headers)
    page = client.get("/v1/changes", params={"since": 0, "limit": 2}, headers=headers).json()
    assert len(page["changes"]) == 2 and page["has_more"] is True
    rest = client.get("/v1/changes", params={"since": page["next_since"], "limit": 10}, headers=headers).json()
    assert len(rest["changes"]) == 3 and rest["has_more"] is False


def test_record_ids_must_look_random(client, first_device):
    headers, _ = first_device
    bad = change("Tasks/Call GCD.md")
    assert client.post("/v1/records", json={"changes": [bad]}, headers=headers).status_code == 422


def test_oversized_record_rejects_whole_batch(make_app, setup_code):
    from fastapi.testclient import TestClient

    client = TestClient(make_app(max_record_bytes=16))
    token = client.post("/v1/setup", json={"setup_code": setup_code, "device_name": "Mac"}).json()["token"]
    headers = {"Authorization": f"Bearer {token}"}
    batch = [change(rid(), blob=b"\x01small"), change(rid(), blob=b"\x01" + b"x" * 64)]
    assert client.post("/v1/records", json={"changes": batch}, headers=headers).status_code == 413
    assert client.get("/v1/changes", headers=headers).json()["changes"] == []


def test_blob_round_trip_and_integrity(client, first_device):
    headers, _ = first_device
    data = b"\x01" + secrets.token_bytes(4096)
    blob_id = hashlib.sha256(data).hexdigest()
    assert client.put(f"/v1/blobs/{blob_id}", content=data, headers=headers).json()["size"] == len(data)
    assert client.get(f"/v1/blobs/{blob_id}", headers=headers).content == data
    wrong = hashlib.sha256(b"other").hexdigest()
    assert client.put(f"/v1/blobs/{wrong}", content=data, headers=headers).status_code == 400
    assert client.get(f"/v1/blobs/{'0' * 64}", headers=headers).status_code == 404
    assert client.get("/v1/blobs/..", headers=headers).status_code == 404


def test_blob_size_limit(make_app, setup_code):
    from fastapi.testclient import TestClient

    client = TestClient(make_app(max_blob_bytes=10))
    token = client.post("/v1/setup", json={"setup_code": setup_code, "device_name": "Mac"}).json()["token"]
    data = b"x" * 100
    resp = client.put(
        f"/v1/blobs/{hashlib.sha256(data).hexdigest()}", content=data, headers={"Authorization": f"Bearer {token}"}
    )
    assert resp.status_code == 413
