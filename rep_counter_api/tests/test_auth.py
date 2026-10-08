from app import mailer
from tests.conftest import auth, register


def test_register_login_and_me(client):
    tokens = register(client)
    assert tokens["user"]["hasPassword"] is True
    assert client.get("/me", headers=auth(tokens)).json()["email"] == "camila@correo.com"

    # El correo no distingue mayúsculas.
    r = client.post("/auth/login", json={"email": "CAMILA@correo.com", "password": "12345678"})
    assert r.status_code == 200


def test_register_twice_is_rejected(client):
    register(client)
    r = client.post(
        "/auth/register",
        json={"name": "Otra", "email": "Camila@Correo.com", "password": "abcdefgh"},
    )
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "email_taken"


def test_wrong_password_and_unknown_email_look_the_same(client):
    register(client)
    a = client.post("/auth/login", json={"email": "camila@correo.com", "password": "nope-nope"})
    b = client.post("/auth/login", json={"email": "nadie@correo.com", "password": "nope-nope"})
    assert a.status_code == b.status_code == 401
    assert a.json() == b.json()


def test_validation_errors_use_the_common_format(client):
    r = client.post("/auth/register", json={"name": "", "email": "x", "password": "123"})
    assert r.status_code == 422
    body = r.json()["error"]
    assert body["code"] == "validation_error"
    assert {d["field"] for d in body["details"]} == {"name", "email", "password"}


def test_requests_without_token_are_rejected(client):
    assert client.get("/me").status_code == 401
    assert client.get("/me", headers={"Authorization": "Bearer basura"}).status_code == 401


def test_refresh_rotates_and_detects_reuse(client):
    tokens = register(client)
    first = tokens["refreshToken"]

    r = client.post("/auth/refresh", json={"refreshToken": first})
    assert r.status_code == 200
    second = r.json()["refreshToken"]
    assert second != first

    # Reusar el viejo indica robo: se cierran todas las sesiones...
    r = client.post("/auth/refresh", json={"refreshToken": first})
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "refresh_token_reused"
    # ...incluida la del token nuevo.
    assert client.post("/auth/refresh", json={"refreshToken": second}).status_code == 401


def test_logout_revokes_the_refresh_token(client):
    tokens = register(client)
    r = client.post("/auth/logout", json={"refreshToken": tokens["refreshToken"]})
    assert r.status_code == 204
    assert client.post("/auth/refresh", json={"refreshToken": tokens["refreshToken"]}).status_code == 401


def test_password_reset(client):
    tokens = register(client)
    mailer.outbox.clear()

    r = client.post("/auth/forgot-password", json={"email": "camila@correo.com"})
    assert r.status_code == 202
    # Un correo inexistente responde igual y no envía nada.
    r2 = client.post("/auth/forgot-password", json={"email": "nadie@correo.com"})
    assert r2.status_code == 202 and r2.json() == r.json()
    assert len(mailer.outbox) == 1

    code = mailer.outbox[0]["token"]
    r = client.post("/auth/reset-password", json={"token": code, "newPassword": "nueva-clave-1"})
    assert r.status_code == 204
    # El código sirve una sola vez.
    r = client.post("/auth/reset-password", json={"token": code, "newPassword": "otra-clave-2"})
    assert r.status_code == 400

    assert client.post(
        "/auth/login", json={"email": "camila@correo.com", "password": "nueva-clave-1"}
    ).status_code == 200
    # Las sesiones abiertas con la contraseña vieja se cerraron.
    assert client.post("/auth/refresh", json={"refreshToken": tokens["refreshToken"]}).status_code == 401


def test_google_is_disabled_without_client_ids(client):
    r = client.post("/auth/google", json={"idToken": "x" * 40})
    assert r.status_code == 503


def test_change_password_and_delete_account(client):
    tokens = register(client)
    h = auth(tokens)
    r = client.put("/me/password", headers=h, json={"currentPassword": "mal", "newPassword": "nueva-clave"})
    assert r.status_code == 403
    r = client.put(
        "/me/password", headers=h, json={"currentPassword": "12345678", "newPassword": "nueva-clave"}
    )
    assert r.status_code == 204

    assert client.request("DELETE", "/me", headers=h, json={"password": "12345678"}).status_code == 403
    assert client.request("DELETE", "/me", headers=h, json={"password": "nueva-clave"}).status_code == 204
    assert client.get("/me", headers=h).status_code == 401
