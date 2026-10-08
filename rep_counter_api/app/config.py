from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuración por variables de entorno (o un archivo .env)."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://repcounter:repcounter@localhost:55432/repcounter"

    # Clave para firmar los tokens de acceso. En producción, una cadena larga y
    # aleatoria que no esté en el repositorio.
    jwt_secret: str = "dev-only-change-me-dev-only-change-me"
    access_token_minutes: int = 15
    refresh_token_days: int = 60
    password_reset_minutes: int = 30

    # Client IDs de Google (Android, iOS, web) separados por coma. Vacío
    # desactiva el inicio de sesión con Google.
    google_client_ids: str = ""

    # "dev" imprime en consola los correos de recuperación en vez de enviarlos.
    app_env: str = "dev"

    # Máximo de sesiones por subida en lote.
    max_batch_sessions: int = 50

    @property
    def google_audiences(self) -> list[str]:
        return [c.strip() for c in self.google_client_ids.split(",") if c.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
