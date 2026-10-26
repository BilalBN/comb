"""M0 'done when': an encrypted change round-trips between two devices,
and the server cannot read it."""
import base64

import pytest

from comb_ref import DecryptError, Device, VaultKey, open_record, seal_blob, open_blob

TASK = """---
id: t_8f3k2
type: task
space: CAX
priority: high
urgent: true
status: todo
---
Send revised HCL vault drawings to GCD.
"""


def pair_phone(client, setup_code, tmp_path):
    mac = Device(http=client, key=VaultKey.generate(), name="MacBook")
    mac.setup(setup_code)
    link = mac.start_pairing("https://comb.example.com")
    phone = Device.join(client, link, "Nothing Phone")
    return mac, phone


def test_task_from_phone_lands_as_markdown_on_mac(client, setup_code, tmp_path):
    mac, phone = pair_phone(client, setup_code, tmp_path)
    assert phone.verify_key()

    phone.write_file("Tasks/Send HCL vault drawings.md", TASK)
    assert phone.sync() == []

    vault = tmp_path / "vault"
    mac.sync(vault)
    assert (vault / "Tasks/Send HCL vault drawings.md").read_text() == TASK


def test_edit_in_obsidian_flows_back_to_phone(client, setup_code, tmp_path):
    mac, phone = pair_phone(client, setup_code, tmp_path)
    phone.write_file("Tasks/a.md", TASK)
    phone.sync()
    mac.sync(tmp_path / "vault")

    mac.write_file("Tasks/a.md", TASK.replace("status: todo", "status: done"))
    mac.sync()
    phone_folder = tmp_path / "phone"
    phone.sync(phone_folder)
    assert "status: done" in (phone_folder / "Tasks/a.md").read_text()


def test_server_never_stores_readable_content(client, setup_code, tmp_path, app, settings):
    mac, phone = pair_phone(client, setup_code, tmp_path)
    phone.write_file("Tasks/Send HCL vault drawings.md", TASK)
    _, ct = seal_blob(phone.key, b"photo of the HCL vault wall")
    blob_id = __import__("hashlib").sha256(ct).hexdigest()
    client.put(f"/v1/blobs/{blob_id}", content=ct, headers=phone._headers())
    phone.sync()
    app.state.db.execute("PRAGMA wal_checkpoint(FULL)")

    secrets_on_disk = [b"HCL", b"GCD", b"vault drawings", b"Tasks/", b"photo of the HCL"]
    for path in settings.data_dir.rglob("*"):
        if path.is_file():
            data = path.read_bytes()
            for needle in secrets_on_disk:
                assert needle not in data, f"{needle!r} readable in {path.name}"


def test_wrong_key_cannot_open_records(client, setup_code, tmp_path):
    mac, phone = pair_phone(client, setup_code, tmp_path)
    phone.write_file("Tasks/a.md", TASK)
    phone.sync()
    record = client.get("/v1/changes", headers=mac._headers()).json()["changes"][-1]
    with pytest.raises(DecryptError):
        open_record(VaultKey.generate(), record["record_id"], base64.b64decode(record["blob"]))


def test_server_cannot_swap_records_between_ids(client, setup_code, tmp_path):
    """Ciphertext is bound to its record id, so a tampering server is detected."""
    mac, phone = pair_phone(client, setup_code, tmp_path)
    phone.write_file("Tasks/a.md", "A")
    phone.write_file("Tasks/b.md", "B")
    phone.sync()
    a, b = [r for r in client.get("/v1/changes", headers=mac._headers()).json()["changes"] if r["record_id"] != "0000keycheck0000"]
    with pytest.raises(DecryptError):
        open_record(mac.key, a["record_id"], base64.b64decode(b["blob"]))


def test_conflicting_edits_keep_both_versions(client, setup_code, tmp_path):
    mac, phone = pair_phone(client, setup_code, tmp_path)
    phone.write_file("Tasks/a.md", "original")
    phone.sync()
    mac.sync(tmp_path / "vault")

    mac.write_file("Tasks/a.md", "edited on mac")
    phone.write_file("Tasks/a.md", "edited on phone")
    assert mac.sync() == []
    conflicts = phone.sync()
    assert len(conflicts) == 1
    current = open_record(phone.key, conflicts[0]["record_id"], base64.b64decode(conflicts[0]["current"]["blob"]))
    assert current["content"] == "edited on mac"


def test_attachment_round_trip(client, setup_code, tmp_path):
    mac, phone = pair_phone(client, setup_code, tmp_path)
    blob_id, ct = seal_blob(phone.key, b"jpeg bytes")
    client.put(f"/v1/blobs/{blob_id}", content=ct, headers=phone._headers())
    fetched = client.get(f"/v1/blobs/{blob_id}", headers=mac._headers()).content
    assert open_blob(mac.key, fetched) == b"jpeg bytes"


def test_recovery_key_round_trip_and_typo_detection():
    key = VaultKey.generate()
    text = key.recovery_key()
    assert VaultKey.from_recovery_key(text.lower()) == key
    typo = ("B" if text[0] != "B" else "C") + text[1:]
    with pytest.raises(ValueError):
        VaultKey.from_recovery_key(typo)
