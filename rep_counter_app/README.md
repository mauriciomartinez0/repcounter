# Rep Counter

App Flutter para Android que se conecta al sensor XIAO nRF52840 Sense y muestra
el contador de repeticiones.

El conteo ocurre **en la placa**, no en el teléfono. La app selecciona el
ejercicio, reinicia el contador y muestra el estado. Esa división no es
casualidad: si la pantalla se bloquea a mitad de serie o el Bluetooth se cae un
segundo, la placa sigue contando y el número está correcto cuando vuelves a
mirar.

## Montar el proyecto

Flutter no deja crear un proyecto encima de archivos sueltos, así que se genera
el esqueleto primero y después se copian estos dos archivos encima:

```bash
flutter create rep_counter_app
cd rep_counter_app
# copiar pubspec.yaml y lib/main.dart de este paquete, sobrescribiendo
flutter pub get
```

## Permisos de Android

Sin esto la app compila y corre, pero el escaneo no encuentra nada y no da
ningún error claro. Es el error más común con BLE en Android.

En `android/app/src/main/AndroidManifest.xml`, dentro de `<manifest>` y antes de
`<application>`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Android 11 y anteriores -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="30" />
```

En `android/app/build.gradle` (o `build.gradle.kts`), `minSdk` debe ser **21** o
superior. flutter_blue_plus no compila por debajo de eso.

La primera vez que abras la app, Android va a pedir el permiso de dispositivos
cercanos. Si lo niegas, el escaneo falla en silencio: hay que concederlo a mano
desde los ajustes de la app.

## Correr

```bash
flutter devices        # confirma que el teléfono aparece
flutter run
```

El teléfono necesita depuración USB activada.

## Usar

1. Alimenta la placa con el firmware `rep_counter_ble.ino`. Anuncia como
   `RepCounter`.
2. Abre la app, toca **Buscar sensor**.
3. Elige el ejercicio. Flexiones espera el sensor en el brazo; curl, en la
   mochila.
4. Quédate quieto un segundo en la posición de inicio. La app muestra
   "Quédate quieto" hasta que la placa aprende esa postura de referencia.
5. Haz las repeticiones.

El LED de la placa parpadea en cada repetición contada, así que puedes verificar
el conteo sin mirar el teléfono.

## La barra de ángulo

Debajo del contador hay una barra con el ángulo en vivo. No es decoración: es
exactamente la señal sobre la que corre el contador.

Si una repetición no se cuenta, mira la barra. Si apenas se mueve, tu rango de
movimiento no está llegando al umbral y el problema es de montaje o de posición
del sensor, no del algoritmo. Sin esa barra, una repetición perdida es un
misterio.

## Ajustar los umbrales

Están en el firmware, en `EXERCISE_PROFILES`:

```cpp
const ExerciseProfile EXERCISE_PROFILES[] = {
  { "push-up",     25.0f, 12.0f, 500 },   // entrar, salir, refractario ms
  { "biceps curl", 45.0f, 20.0f, 450 },
};
```

Los elegí a ojo para un rango de movimiento típico. Es muy probable que haya que
ajustarlos con tu montaje real, y la barra de ángulo te dice hacia dónde:

- **Cuenta de más**: sube el umbral de entrada, o separa más los dos valores.
- **No cuenta**: baja el umbral de entrada por debajo del pico que veas.
- **Cuenta doble en una repetición**: sube el refractario.

El hueco entre entrada y salida es la histéresis, y existe para que un temblor
justo en el umbral no dispare varias cuentas.

## Protocolo BLE

Por si quieres hablarle desde otro lado, como un script en Python con `bleak`:

```
Servicio  a1b20001-7f3c-4e8d-9a6b-2c5d8e0f1a3b
Estado    a1b20002-...  notify, 6 bytes little endian
Control   a1b20003-...  write
```

Paquete de estado:

| Offset | Tipo   | Campo |
|--------|--------|-------|
| 0..1   | uint16 | repeticiones |
| 2..3   | int16  | ángulo en décimas de grado |
| 4      | uint8  | id del ejercicio |
| 5      | uint8  | bit 0 = fase alta, bit 1 = referencia capturada |

Comandos de control:

| Bytes        | Acción |
|--------------|--------|
| `0x01 <id>`  | cambiar de ejercicio |
| `0x02`       | reiniciar el contador |
| `0x03`       | recapturar la postura de reposo |

## Pantallas y estructura

La app sigue los diseños de `contador-repeticiones-parte-1/2.html`: cuenta,
conexión del sensor, rutinas, catálogo de ejercicios, entrenamiento
(calibración → contador → descanso → resumen) e historial con progreso.

```
lib/
  main.dart, app.dart, app_scope.dart   arranque y servicios compartidos
  config.dart   URL de la API y opciones de compilación
  api/          cliente HTTP: tokens, renovación, errores
  theme/        colores, tipografía (Barlow) e íconos de la guía de estilos
  data/         modelos, repositorio remoto (API + copia local) y local (pruebas)
  sensor/       BLE con la placa + sensor simulado
  workout/      lógica del entrenamiento en curso
  screens/      una carpeta por sección
  widgets/      componentes compartidos y gráficas
```

## Servidor

La cuenta, las rutinas, el historial y los favoritos viven en la API
(`../rep_counter_api`). La app guarda una copia en el teléfono y una cola de
cambios pendientes, así que se puede entrenar sin internet: todo se sube solo
cuando vuelve la señal, al abrir la app o desde Ajustes → Sincronización.

- Los tokens van en el almacenamiento seguro del teléfono (Keystore), nunca
  en SharedPreferences.
- Un entrenamiento se sube al tocar "Listo" en el resumen, para que las
  correcciones de repeticiones vayan incluidas.
- Al cerrar sesión se borra la copia local de esa cuenta; si hay cambios sin
  subir, la app avisa antes.

La URL del servidor se define al compilar, en `config/`:

| Archivo | Para qué |
|---|---|
| `config/dev.json` | API en tu computador (`http://192.168.0.101:8000`). Solo debug permite http. |
| `config/prod.json` | API en Railway. **Pon tu dominio en `API_BASE_URL`** (con https). |

```bash
# Desarrollo: API local (ver ../rep_counter_api/README.md) y teléfono en la misma red
flutter run --dart-define-from-file=config/dev.json

# Producción
flutter build appbundle --dart-define-from-file=config/prod.json
```

Si se compila sin URL, o en release con http, la app lo dice en pantalla en
vez de fallar con errores de red.

## Firma para Play Store

Sin llave propia, la versión release se firma con la llave de debug: sirve
para probar, no para publicar. Para publicar:

```bash
keytool -genkey -v -keystore ~/repcounter-upload.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias upload
```

y crea `android/key.properties` (ya está en `.gitignore`):

```
storeFile=/home/mauro/repcounter-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Guarda la llave y las contraseñas fuera del repositorio y con respaldo: sin
ellas no se puede actualizar la app publicada.

## Pruebas

```bash
flutter test                                  # unitarias
API_TEST_URL=http://localhost:8000 \
  flutter test test/api_integration_test.dart  # contra la API real
```

Las de integración registran varias cuentas seguidas, así que la API local
debe correr sin el límite de intentos (si no, responde 429 desde la décima):

```bash
cd ../rep_counter_api
APP_ENV=dev RATE_LIMIT_ENABLED=false .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## Probar sin la placa

```bash
flutter run --dart-define-from-file=config/dev.json --dart-define=SENSOR_SIM=true
```

El sensor simulado se conecta, calibra y hace series de 8 a 12 repeticiones.

## Pendiente

- **Dominio de producción** en `config/prod.json`.
- **Application ID:** sigue siendo `com.example.rep_counter_app`. Play Store
  no acepta `com.example`; hay que elegir uno propio (por ejemplo
  `com.tudominio.repcounter`) antes de publicar, porque después no se puede
  cambiar.
- **Recuperar contraseña y acceso con Google:** la API ya los tiene, faltan
  las pantallas, el proveedor de correo y los client IDs de Google.
- **Velocidad media:** la placa no la envía todavía. La app ya lee 2 bytes
  extra opcionales en la notificación (velocidad de la última repetición en
  mm/s, entero sin signo, little-endian); falta agregarlos al firmware.
- **Videos de tutorial:** el reproductor es de muestra hasta que haya videos.
- **Ilustraciones de colocación:** solo la barra tiene dibujo propio; brazo,
  cuerpo, mancuerna, máquina y polea usan el ícono grande.
- **Perfiles del firmware:** la placa conoce dos (0 = brazo o barra,
  1 = torso). Si hacen falta umbrales distintos por ejercicio, el firmware
  debe aceptar el umbral o más perfiles.
- **Probar en un teléfono con la placa real:** hasta ahora se probó con el
  sensor simulado y pruebas automáticas.

