"""Forma del JSON de la API. Usa camelCase y los mismos nombres de campo que
los modelos de la app (lib/data/models.dart)."""

from datetime import datetime
from enum import StrEnum
from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    StringConstraints,
    model_validator,
)
from pydantic.alias_generators import to_camel


class Model(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
Password = Annotated[str, StringConstraints(min_length=8, max_length=128)]
ExerciseId = Annotated[str, StringConstraints(pattern=r"^[a-z0-9]+(-[a-z0-9]+)*$", max_length=64)]
WeightKg = Annotated[float, Field(gt=0, le=500)]


# --- Cuenta -----------------------------------------------------------------


class User(Model):
    id: UUID
    name: str
    email: str
    has_password: bool
    has_google: bool
    created_at: datetime


class AuthResponse(Model):
    user: User
    access_token: str
    refresh_token: str
    token_type: Literal["Bearer"] = "Bearer"
    # Segundos de vida del access token.
    expires_in: int


class RegisterIn(Model):
    name: Name
    email: EmailStr
    password: Password


class LoginIn(Model):
    email: EmailStr
    password: Annotated[str, StringConstraints(min_length=1, max_length=128)]


class GoogleIn(Model):
    id_token: Annotated[str, StringConstraints(min_length=10)]


class RefreshIn(Model):
    refresh_token: Annotated[str, StringConstraints(min_length=10, max_length=200)]


class ForgotPasswordIn(Model):
    email: EmailStr


class ResetPasswordIn(Model):
    token: Annotated[str, StringConstraints(min_length=10, max_length=200)]
    new_password: Password


class UpdateMeIn(Model):
    name: Name


class ChangePasswordIn(Model):
    # Opcional para cuentas que solo tenían Google y agregan contraseña.
    current_password: str | None = None
    new_password: Password


class DeleteMeIn(Model):
    # Obligatoria si la cuenta tiene contraseña.
    password: str | None = None


class ExerciseSummary(Model):
    exercise_id: str
    last_done_at: datetime
    last_weight_kg: float | None


# --- Catálogo ---------------------------------------------------------------


class MuscleGroup(StrEnum):
    chest = "chest"
    back = "back"
    legs = "legs"
    shoulders = "shoulders"
    arms = "arms"
    core = "core"


class Equipment(StrEnum):
    barbell = "barbell"
    dumbbell = "dumbbell"
    machine = "machine"
    bodyweight = "bodyweight"
    cable = "cable"


class SensorPlacement(StrEnum):
    arm = "arm"
    body = "body"
    equipment = "equipment"


class Exercise(Model):
    id: str
    name: str
    muscle_group: MuscleGroup
    equipment: Equipment
    placement: SensorPlacement
    placement_note: str
    firmware_profile: int
    threshold_degrees: int
    tutorial_steps: list[str]
    tutorial_seconds: int
    video_url: str | None
    # Los retirados se siguen enviando para que el historial muestre su nombre;
    # la app no los ofrece para entrenamientos nuevos.
    active: bool


class Catalog(Model):
    version: str
    exercises: list[Exercise]


# --- Rutinas ----------------------------------------------------------------


class RoutineItem(Model):
    exercise_id: ExerciseId
    sets: Annotated[int, Field(ge=1, le=20)]
    reps: Annotated[int, Field(ge=1, le=100)]
    weight_kg: WeightKg | None = None
    rest_seconds: Annotated[int, Field(ge=0, le=900)]


class RoutineIn(Model):
    name: Name
    items: Annotated[list[RoutineItem], Field(max_length=50)]
    # Cuándo editó el usuario en el teléfono. Si el servidor ya tiene una
    # edición posterior, gana esa.
    edited_at: AwareDatetime


class Routine(Model):
    id: UUID
    name: str
    items: list[RoutineItem]
    created_at: datetime
    edited_at: datetime
    updated_at: datetime
    # Presente cuando la rutina se borró: el teléfono debe quitarla.
    deleted_at: datetime | None


class RoutineWriteResult(Model):
    routine: Routine
    # False si el servidor ya tenía una versión editada después y se quedó
    # con ella; la app debe reemplazar su copia por `routine`.
    applied: bool


class RoutineChanges(Model):
    routines: list[Routine]
    # Pasar como `since` en la siguiente sincronización.
    server_time: datetime


# --- Sesiones ---------------------------------------------------------------


class SetRecord(Model):
    exercise_id: ExerciseId
    set_number: Annotated[int, Field(ge=1, le=100)]
    reps: Annotated[int, Field(ge=0, le=1000)]
    target_reps: Annotated[int, Field(ge=1, le=1000)] | None = None
    weight_kg: WeightKg | None = None
    mean_velocity: Annotated[float, Field(ge=0, le=10)] | None = None
    range_degrees: Annotated[float, Field(ge=0, le=180)] | None = None
    completed_at: AwareDatetime


class SessionIn(Model):
    # Generado por el teléfono al empezar el entrenamiento. Reenviar la misma
    # sesión con el mismo id no la duplica.
    id: UUID
    routine_id: UUID | None = None
    title: Name
    started_at: AwareDatetime
    ended_at: AwareDatetime
    planned_exercises: Annotated[int, Field(ge=0, le=100)] = 0
    sets: Annotated[list[SetRecord], Field(min_length=1, max_length=300)]

    @model_validator(mode="after")
    def _times(self):
        if self.ended_at < self.started_at:
            raise ValueError("endedAt no puede ser anterior a startedAt")
        return self


class Session(Model):
    id: UUID
    routine_id: UUID | None
    title: str
    started_at: datetime
    ended_at: datetime
    planned_exercises: int
    received_at: datetime
    volume_kg: float
    sets: list[SetRecord]


class SessionUploadResult(Model):
    # "created": se guardó ahora. "duplicate": ya estaba (reintento), no se
    # tocó nada y `session` es la versión guardada.
    status: Literal["created", "duplicate"]
    session: Session


class SessionBatchIn(Model):
    # Se valida cada una por separado: una sesión mal formada se rechaza sola
    # sin bloquear al resto de la cola.
    sessions: Annotated[list[dict[str, Any]], Field(min_length=1)]


class SessionBatchItem(Model):
    id: UUID
    # "rejected": no se guardará nunca así; la app debe sacarla de la cola y
    # avisar. Los errores temporales (red, 5xx) no llegan aquí.
    status: Literal["created", "duplicate", "rejected"]
    error: dict | None = None


class SessionBatchResult(Model):
    results: list[SessionBatchItem]


class SessionPage(Model):
    sessions: list[Session]
    # Pasar como `cursor` para la página siguiente; null si no hay más.
    next_cursor: str | None


class SessionChanges(Model):
    sessions: list[Session]
    # Pasar como `since` en la siguiente llamada.
    server_time: datetime
    # True si hay más: volver a llamar enseguida con el nuevo `since`.
    has_more: bool


# --- Progreso ---------------------------------------------------------------


class Metric(StrEnum):
    weight = "weight"
    reps = "reps"
    volume = "volume"
    one_rep_max = "oneRepMax"
    velocity = "velocity"
    range = "range"


class ProgressRange(StrEnum):
    weeks4 = "4w"
    weeks12 = "12w"
    all = "all"


class ProgressPoint(Model):
    date: datetime
    value: float


class Progress(Model):
    exercise_id: str
    metric: Metric
    range: ProgressRange
    points: list[ProgressPoint]
    latest: ProgressPoint | None
    best: ProgressPoint | None
    average: float | None
    # Último punto menos el primero del periodo.
    change: float | None
