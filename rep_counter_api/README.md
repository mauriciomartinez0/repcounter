# Rep Counter API

Backend de la app del contador de repeticiones: cuentas, catálogo de
ejercicios, rutinas e historial. FastAPI + PostgreSQL 17.

El conteo sigue ocurriendo en la placa; el servidor solo guarda lo que la app
le manda.

## Correr

Con Docker Compose (base de datos + API en http://localhost:8000):

```bash
docker compose up --build
```

O a mano, con la base en Docker y la API en tu máquina:

```bash
docker run -d --name repcounter-db -p 55432:5432 \
  -e POSTGRES_USER=repcounter -e POSTGRES_PASSWORD=repcounter -e POSTGRES_DB=repcounter \
  postgres:17-alpine
cp .env.example .env    # APP_ENV=dev para desarrollo
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m app.migrate
.venv/bin/uvicorn app.main:app --reload
```

Documentación interactiva de todos los endpoints: http://localhost:8000/docs

Pruebas (crean y borran su propia base `repcounter_test`):

```bash
.venv/bin/pytest
```

## Base de datos

El esquema está en `db/migrations/`, en SQL comentado. `python -m app.migrate`
aplica las que falten, en orden y una sola vez; la imagen de Docker lo hace al
arrancar. Para cambiar el esquema se agrega un archivo nuevo
(`003_...sql`); nunca se editan los ya aplicados.

| Tabla | Contenido |
|---|---|
| `users` | cuenta; contraseña (argon2) y/o Google |
| `refresh_tokens`, `password_reset_tokens` | solo hashes, nunca el token |
| `exercises`, `tutorial_steps` | catálogo, administrado por el equipo |
| `favorites` | favoritos de cada usuario |
| `routines`, `routine_items` | rutinas; las borradas quedan como "lápida" |
| `workout_sessions`, `set_records` | historial; inmutable una vez subido |

## Catálogo de ejercicios

Vive en la base de datos. La app trae una copia incluida para funcionar sin
internet y la actualiza con `GET /exercises` mandando `If-None-Match` con la
versión que tiene: si no cambió, la respuesta es `304` y no se descarga nada.
Para agregar o corregir ejercicios, una migración nueva con `INSERT`/`UPDATE`.
Un ejercicio no se borra: se marca `active = false` para que el historial
siga mostrándolo.

## Uso sin conexión: cómo debe sincronizar la app

En el gimnasio puede no haber señal, así que la app guarda todo primero en el
teléfono y lo sube cuando puede. La API está hecha para que eso sea seguro:

1. **Los ids los genera el teléfono** (UUID v4) al crear una rutina o al
   empezar un entrenamiento. Nunca cambian.
2. **Reintentar no duplica.** Si se cae la red después de que el servidor
   guardó, la app reenvía y recibe `"status": "duplicate"` con lo guardado.
   Tanto `created` como `duplicate` significan "ya está, sácalo de la cola".
3. **Rutinas: gana la edición más reciente.** `PUT /routines/{id}` lleva
   `editedAt` (hora del teléfono al editar). Si el servidor ya tiene una edición
   posterior, responde `"applied": false` con esa versión, y la app reemplaza
   la suya.
4. **Los borrados se propagan.** `DELETE` deja una lápida; los otros teléfonos
   la reciben con `deletedAt` en `GET /routines?since=...`.

Orden de cada sincronización:

```
1. GET  /exercises            (If-None-Match)        catálogo
2. PUT  /routines/{id}        por cada rutina pendiente
   DELETE /routines/{id}      por cada borrado pendiente
3. POST /sessions/batch       la cola de sesiones, hasta 50 por envío
4. GET  /routines?since=T1    cambios hechos en otros teléfonos
5. GET  /sessions/sync?since=T2  (repetir mientras hasMore)
   Guardar serverTime de 4 y 5 como T1 y T2 para la próxima vez.
```

Las rutinas van antes que las sesiones: una sesión que referencia una rutina
que el servidor no conoce se rechaza con `unknown_routine`.

Qué hacer con cada respuesta:

| Respuesta | Qué hace la app |
|---|---|
| `created`, `duplicate`, `204` | quitar de la cola |
| `rejected` en el lote, `409`, `410`, `422` | quitar de la cola y avisar (no se arreglará reintentando) |
| `401` | renovar con `POST /auth/refresh` y reintentar |
| sin red, timeout, `5xx` | dejar en la cola y reintentar más tarde |

## Cuenta y tokens

- `accessToken`: JWT de 15 minutos, en `Authorization: Bearer ...`.
- `refreshToken`: 60 días, de un solo uso. `POST /auth/refresh` lo cambia por
  uno nuevo. Si un token ya usado vuelve a aparecer, se asume robo y se cierran
  todas las sesiones de la cuenta.
- Los errores siempre tienen la forma
  `{"error": {"code": "...", "message": "..."}}`; `message` está en español y
  se puede mostrar tal cual.

## Pendiente antes de producción

- **Correo:** `app/mailer.py` no envía nada todavía (en desarrollo imprime el
  código de recuperación en el log). Falta elegir proveedor.
- **Google:** poner los client IDs en `GOOGLE_CLIENT_IDS`; sin ellos,
  `/auth/google` responde 503.
- **`JWT_SECRET`** propio y largo, fuera del repositorio. Sin `APP_ENV=dev`,
  la API no arranca si falta o tiene menos de 32 caracteres.
- **Límite de intentos:** ya hay uno por IP en las rutas de cuenta
  (`app/ratelimit.py`), en memoria. Si algún día corren varias instancias de la
  API, moverlo a Redis.
- **HTTPS** delante (Caddy, Nginx o la plataforma donde se despliegue) y
  respaldos de PostgreSQL.
- **Errores de red con Google:** si no se pueden descargar los certificados de
  Google, `/auth/google` responde 500 en vez de un 503 claro.
- **Sincronización de sesiones con muchas al mismo tiempo:** `GET
  /sessions/sync` pagina por hora de llegada; si más de 200 sesiones llegaran
  en el mismo instante, la paginación no avanzaría. Con lotes de 50 no pasa,
  pero conviene pasar a un cursor (hora + id) como en `GET /sessions`.

## Pendiente en la app

La app ya está conectada (registro, inicio de sesión, catálogo, rutinas,
sesiones y favoritos, con cola sin conexión). Falta:

- Pantallas de recuperación de contraseña (pedir el código y poner la nueva).
- Acceso con Google en el teléfono (`google_sign_in`) enviando el ID token a
  `/auth/google`.
- Subir videos de tutorial a un almacenamiento (S3 o similar) y llenar
  `video_url`; reproducirlos con `video_player`.
