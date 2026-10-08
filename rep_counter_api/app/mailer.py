"""Envío de correos. Falta elegir un proveedor (SES, Postmark, SMTP propio) y
poner aquí su llamada. Mientras tanto, en desarrollo el mensaje se imprime en
el log y se guarda en `outbox` (las pruebas lo leen de ahí); fuera de
desarrollo no se envía nada."""

import logging

from app.config import get_settings

log = logging.getLogger("repcounter.mail")

outbox: list[dict] = []


def send_password_reset(email: str, name: str, token: str) -> None:
    if get_settings().app_env != "dev":
        log.error("No hay proveedor de correo: no se envió la recuperación a %s", email)
        return
    outbox.append({
        "to": email,
        "subject": "Recupera tu contraseña",
        "body": (
            f"Hola {name}:\n\nUsa este código en la app para elegir una contraseña "
            f"nueva. Vence en 30 minutos.\n\n{token}\n\n"
            "Si no lo pediste, ignora este correo."
        ),
        "token": token,
    })
    log.warning("[dev] Código de recuperación para %s: %s", email, token)
