# Rep Counter — iOS nativo

Puerto a Swift / SwiftUI de la app Flutter (`rep_counter_app/`), para poder
instalarla en el iPhone desde Arch con [xtool](https://github.com/xtool-org/xtool).

Es la misma app, pantalla por pantalla: inicio de sesión y registro contra la
API de Railway, conexión del sensor, rutinas (lista, detalle, editor), catálogo
de ejercicios con favoritos y tutorial, flujo de entrenamiento (calibración →
contador → descanso → resumen con correcciones), historial, progreso por
ejercicio, ajustes con modo oscuro y sincronización offline. Usa los mismos
colores, las mismas fuentes (Barlow y Barlow Condensed), los mismos íconos y el
mismo formato de datos, así que comparte cuenta e historial con la versión
Flutter.

## Estructura

```
Package.swift                 un solo producto library: xtool lo empaqueta como .app
xtool.yml                     bundleID, Info.plist e ícono
Info.plist                    se FUSIONA con el que genera xtool (Bluetooth, URL de la API)
Resources/AppIcon.png         el mismo ícono de la app Flutter
Sources/RepCounter/
  App/        RepCounterApp (entrada, servicios, raíz), Router (navegación)
  API/        ApiClient: tokens en el Keychain, refresco automático
  Data/       modelos, catálogo semilla, repositorio con cola offline, sesión y ajustes
  Sensor/     SensorService: CoreBluetooth y un simulador
  Workout/    WorkoutController: series, descanso, calibración; TraceRecorder: recorrido
  Theme/      colores, tipografía, íconos SVG, formato de números y fechas
  Widgets/    botones, campos, chips, gráfica, diálogos y hojas
  Screens/    todas las pantallas
  Resources/Fonts/  Barlow (licencia OFL)
```

Cada archivo Swift corresponde a uno o varios `.dart` de `rep_counter_app/lib`
con los mismos nombres de tipos y funciones, para que un cambio en una versión
sea fácil de llevar a la otra.

## Catálogo de ejercicios e imágenes

192 ejercicios: los 32 originales más 160 elegidos del dataset abierto
[hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset),
con nombre en español y los pasos del tutorial en el español que trae el
dataset. Cada uno tiene su miniatura de 180×180 en
`Resources/ExerciseImages/<id>.jpg`, que se muestra a la izquierda en la lista,
y una demostración en la ficha del ejercicio, junto a los pasos de "Cómo
hacerlo":

- **170 ejercicios** usan dos fotos reales (posición inicial y final) de
  [free-exercise-db](https://github.com/yuhonas/free-exercise-db), que se
  alternan con un fundido: `Resources/ExercisePhotos/<id>-0.jpg` y `-1.jpg`,
  640 px de ancho, 15 MB en total. El mapeo está en `tools/catalog/photos.py`.
- **Los otros 22**, sin equivalente fiel ahí, usan la animación del dataset
  (`Resources/ExerciseAnimations/<id>.gif`). Esa animación mide 180×180 y su
  licencia prohíbe distribuirla a más resolución, así que se muestra a 200 pt
  como máximo.

Todo va dentro de la app, así que funciona sin internet.

- La lista curada está en `tools/catalog/curated.py`. `generate.py` (con la
  ruta de un clon del dataset como argumento) regenera las migraciones
  `rep_counter_api/db/migrations/003_dataset_exercises.sql`, `004_weight_stack.sql`
  y `005_more_exercises.sql`, el catálogo semilla
  `Resources/Catalog/catalog.json`, las miniaturas, las fotos y las
  animaciones (descarga las fotos la primera vez). La 003 y la 004 ya están
  aplicadas en producción y salen idénticas: los ejercicios nuevos van en la
  lista `LATER` de `curated.py`, que termina en la 005. Cuando la 005 también
  esté aplicada, lo que siga necesita una 006.
- **El catálogo lo manda la API.** La app lo reemplaza en cada sincronización,
  así que los ejercicios nuevos solo aparecen cuando la migración está aplicada
  en el servidor.
- Las imágenes son © Gym visual (https://gymvisual.com/), que el dataset
  redistribuye con permiso a 180×180 y con la condición de mantener el crédito
  (está al final de la lista de ejercicios y debajo de cada animación). Los datos del dataset son MIT.
- free-exercise-db se publica como Unlicense (dominio público), pero no
  documenta de dónde salieron sus fotos. Para uso personal no hay problema; si
  algún día la app se publica, conviene confirmar su origen.

## Batería del sensor

El firmware (`rep_counter_ble.ino`) mide la LiPo de la XIAO cada 10 s y publica
el porcentaje con el Battery Service estándar de BLE (0x180F / 0x2A19). La app
lo muestra junto al indicador "SENSOR" mientras está conectado; a partir de
15 % se resalta. Con firmware anterior simplemente no aparece.

- El porcentaje sale del voltaje con la curva de descarga de una LiPo, así que
  es una estimación. **Con el cable USB conectado marca cerca de 100 %**,
  porque mide el voltaje de carga, no el de la batería en reposo.
- El divisor de la XIAO (1 MΩ / 510 kΩ) es una fuente de ~340 kΩ, así que el
  ADC mide con 40 µs de adquisición (`analogSampleTime(40)`). Con los 3 µs que
  trae el core por defecto la lectura salía baja y cambiaba bastante de una
  conexión a otra. El porcentaje publicado solo cambia de 2 en 2 o más, porque
  en la parte plana de la curva 3 mV ya son 1 %.
- iOS guarda en caché los servicios de cada dispositivo. Si después de cargar
  el firmware nuevo no aparece la batería, olvida el sensor en Ajustes →
  Bluetooth o apaga y prende el Bluetooth.

## Sensor sobre la pila de pesas

En los 30 ejercicios de polea y las 17 máquinas de selector (se cambia el
pasador, no discos: pec deck, jalones, extensión de piernas…) el sensor va
encima de la pila, pegado a la placa superior. La pila sube y baja sin girar,
así que esos ejercicios usan el perfil 2 del firmware, que cuenta por
velocidad vertical en lugar de inclinación. En el contador se ve hacia dónde va
la pila y a qué velocidad, en vez de la barra de ángulo.

- Si no se puede pegar arriba, sirve de costado en la placa superior (o en
  cualquiera por encima del pasador): la placa usa el largo de la
  aceleración (1 g más la aceleración vertical), que no depende de cómo esté
  girado el sensor. Por eso tampoco se desajusta si se desliza o queda
  torcido, y se puede probar con el sensor en la mano, moviéndolo de arriba
  abajo. Antes proyectaba sobre la vertical de la calibración: con 10° de
  giro la gravedad se colaba (15 mg), la velocidad derivaba y el conteo se
  quedaba en 0 aunque la curva mostrara las ondas. Lo que sí estorba es
  mucho movimiento de lado y rápido (en simulación, 8 cm a 0,9 s por
  repetición), que una pila no tiene.
- La lista está en `tools/catalog/curated.py` (`SELECTOR_MACHINES`; las poleas
  entran todas) y llega al servidor con la migración 004.
- Las máquinas de discos (prensa, hack, remo en T, remo alto, Smith, talones)
  no tienen pila y siguen como antes.
- **Cuenta por el periodo de la curva.** La placa integra la velocidad a
  altura (la misma onda que se ve en la gráfica del recorrido) y cada valle →
  pico → valle es una onda. Cuentan las ondas que se repiten: la primera
  espera a una segunda parecida (amplitud dentro de ~3×, periodo dentro de
  2×) y entonces aparecen las dos; después, cada onda cuenta si su periodo
  está entre un tercio y el triple del habitual y no es mucho más chica
  (30 % de la habitual o 60 % de la anterior). Agarrar, soltar o reacomodar
  el agarre hace ondas chicas que no se parecen a las de la serie, así que
  no hay nada que configurar: el antiguo ajuste "Sube al agarrar" ya no
  existe y la placa ignora su comando (`0x05`).
- Una serie de una sola repetición no se cuenta en vivo (no hay periodo con
  qué compararla). Agarrar y soltar varias veces seguidas sin hacer
  repeticiones sí puede contar, porque esas ondas también se repiten.
- **Sensibilidad**: en el contador y en el descanso hay un control deslizante,
  de "Estricto" a "Flexible", que se puede mover en plena serie (comando
  `0x06`, 0–100, 50 por defecto). En la pila mueve a la vez todos los umbrales
  del conteo por periodo (`stack::tuningFor`): cuánto tiene que bajar la pila
  para cerrar una onda, qué tan chica puede ser una repetición frente a las
  demás, la onda mínima y el margen del periodo; en los ejercicios de
  inclinación, los mismos umbrales en grados. Se guarda por ejercicio en el
  teléfono y se vuelve a mandar al reconectar. Más flexible cuenta repeticiones cortas o incompletas, y
  también es más fácil que sume agarrar o soltar el agarre.
- Los umbrales del perfil 2 se ajustaron con series simuladas
  (`rep_counter_ble/stack_sim.py`) y falta confirmarlos con series reales.

### Revisión al terminar la serie

En esos ejercicios la placa cuenta en vivo y además graba la serie. Al
cerrarla, la app le pide el análisis (comando `0x04`, respuesta por la
característica `a1b20004`) y la placa repasa toda la serie como describe
`TRASPASO.md`: reposos, ZUPT anclado en sus bordes, filtro de fase cero y
conteo por el signo de la velocidad. Si encuentra más repeticiones que el
conteo en vivo, la app muestra cuántas y deja elegir entre sumarlas o dejar el
conteo en vivo. El conteo nunca se corrige hacia abajo.

- El análisis está en `rep_counter_ble/set_analysis.h` (C++ sin Arduino) y su
  referencia en Python en `set_analysis.py`; `test/set_analysis_test.cpp`
  comprueba que ambos coinciden.
- Con firmware anterior, sin esa característica, la serie se guarda con el
  conteo en vivo, como antes.
- La pantalla de descanso (o un aviso, tras la última serie) dice siempre qué
  pasó con la revisión: coincidió, encontró menos, no estaba disponible…
- Si el ejercicio es de pila y la placa no confirma el perfil 2 (la placa
  informa su perfil en cada paquete), la calibración y el contador avisan que
  el firmware está desactualizado: el firmware anterior ignora ese perfil y
  sigue contando por inclinación, que en la pila no sirve.
- Con el sensor simulado, en los ejercicios de pila a veces "se escapa" una
  repetición en vivo, para poder ver la pantalla de revisión sin la placa.

## Ejercicios de inclinación

Con el sensor en el brazo, el cuerpo o una barra (perfiles 0 y 1), la placa
mide el ángulo respecto de la pose en que calibró y cuenta igual que en la
pila, por el periodo de la curva (`stack::TiltCounter`): cada subida y bajada
del ángulo parecida a las demás es una repetición. Antes había que pasar 25°
al subir y volver por debajo de 12° (45° / 20° en el cuerpo); en las primeras
capturas del modo desarrollador, unas elevaciones laterales que entre
repeticiones se quedaban a 15–25° de la pose inicial contaron 5 de 12 y 2 de
10. Con el conteo por periodo, las mismas capturas dan 12 y 10.

## Recorrido de cada serie

Mientras cuenta, la placa manda su estado unas 20 veces por segundo. La app
graba esos paquetes durante la serie y guarda la curva (10 valores por
segundo) junto con la serie:

- **En la pila de pesas** el paquete trae la velocidad vertical. Integrada da
  la altura de la placa, que sube y baja una vez por repetición, como una
  onda seno. La integral deriva un poco, así que la curva se endereza para que
  la serie termine a la altura en que empezó, y se corre para que el punto más
  bajo sea 0 cm.
- **En los demás ejercicios** es el ángulo que reporta la placa.

La curva aparece en el descanso, justo después de la serie, y en la hoja de
cada ejercicio del resumen (al tocarlo, también desde el historial). Las
series grabadas antes de esto no la tienen. El código está en
`Workout/TraceRecorder.swift` y `Widgets/TraceChart.swift`; viaja a la API en
el campo `trace` de cada serie (migración 006).

## Historial editable

Desde el historial, tocar un ejercicio abre la misma hoja que al terminar el
entrenamiento: se corrigen repeticiones y peso, o se eliminan series, y cada
cambio se sube enseguida (`PUT /sessions/{id}`; si dos teléfonos corrigen la
misma sesión sin conexión, gana la corrección posterior). "Eliminar
entrenamiento", al final del resumen, la borra también en los demás teléfonos
(`DELETE /sessions/{id}` deja una lápida que llega por la sincronización).
Eliminar la última serie elimina el entrenamiento.

Cada ejercicio del resumen lleva un lápiz. En la hoja, el peso y las
repeticiones se pueden escribir tocando el número (hasta dos decimales, coma o
punto; vacío o 0 es peso corporal) además de usar − y +. "Agregar serie"
copia la última, sin datos del sensor, y "Agregar ejercicio" suma uno que no
quedó registrado, con una serie como la última vez que se hizo. Todo viaja en
el mismo `PUT`, que reemplaza las series de la sesión; la fecha y el nombre no
se pueden editar porque la API no los recibe.

Necesita la API 1.4.0: con la anterior, las correcciones y los borrados no
llegan al servidor.

## Modo desarrollador

Para revisar el conteo con series reales. Se activa en Ajustes →
Desarrollador. Mientras está activo:

- La app le pide a la placa el acelerómetro crudo (comando `0x07`,
  característica `a1b20005`: 3 lecturas x y z por paquete, 104 Hz, con número
  de secuencia para ver los paquetes perdidos) y graba cada serie desde la
  calibración: el crudo, cada paquete de estado, los eventos (calibración,
  cada repetición, sensibilidad, cierre, análisis) y los conteos.
- Al terminar cada serie pregunta cuántas repeticiones se hicieron de verdad.
- Cada serie es un JSON en `Documents/captures` (formato en
  `Dev/DevCapture.swift`). El **panel desarrollador** (Ajustes → Panel
  desarrollador) las lista con lo que contó la placa y lo real, y en cada una
  muestra la aceleración, la velocidad que calculó la placa, su integral sin
  corregir y el conteo en el tiempo, con una marca en cada repetición
  contada. Se pueden compartir o borrar.

En la computadora, con el iPhone conectado por USB (la app comparte
Documentos: `UIFileSharingEnabled`):

```bash
cd rep_counter_ble/dev
./pull_captures.sh                      # copia las capturas a ./captures
python3 analyze_capture.py captures/*.json
```

`analyze_capture.py` cuenta las repeticiones a partir del crudo (doble
integral por FFT en 0,15–3 Hz y picos claros), estima el periodo, corre el
contador del firmware (`stack_sim.count`) con la magnitud y con la proyección
a sensibilidad 0, 50 y 100, y deja un PNG por captura. `captures/` está en el
`.gitignore`.

Con firmware anterior no llegan datos crudos; el resto de la captura sí.

## Configuración

En `Info.plist`:

- `APIBaseURL`: la URL de la API (hoy la de producción, igual que
  `config/prod.json`). Para probar contra el servidor local pon
  `http://192.168.0.101:8000`; en builds de depuración se permite `http`.
- `SensorSimulated`: `true` para usar el sensor falso y probar todas las
  pantallas sin la placa.

## Instalar xtool en Arch

```bash
# 1. Toolchain de Swift (swiftly)
curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash
swiftly install latest

# 2. usbmuxd, que es lo que habla con el iPhone por USB en Linux
sudo pacman -S usbmuxd

# 3. xtool (paquete AUR xtool-bin)
xtool setup          # autentica con tu Apple ID y extrae el SDK del Xcode.xip
```

El toolchain de swiftly está compilado para Ubuntu y busca `libncurses.so.6` y
`libxml2.so.2`, que en Arch se llaman `libncursesw.so.6` y `libxml2.so.16`.
xtool limpia `LD_LIBRARY_PATH` al llamar al compilador, así que hacen falta
symlinks dentro del toolchain (`usr/lib` y `usr/lib/swift/linux`). Si actualizas
Swift con swiftly hay que volver a crearlos, o configurarlo una sola vez para
todo el sistema:

```bash
echo "$HOME/.local/lib/swift-compat" | sudo tee /etc/ld.so.conf.d/swift-compat.conf
sudo ldconfig
```

## Compilar e instalar

```bash
cd rep_counter_ios
xtool dev            # compila, firma e instala en el iPhone conectado
xtool dev build      # solo compila
```

`usbmuxd` arranca solo al conectar el iPhone; no hace falta habilitarlo.

## Las limitaciones de la cuenta gratuita

| | |
|---|---|
| Caducidad del perfil | **7 días** → reinstalar con `xtool dev` cada semana |
| Apps por dispositivo | máximo 3 |
| App IDs | 10 cada 7 días |

## Diferencias con la versión Flutter

Son pocas y vienen de la plataforma:

- **Reordenar ejercicios en el editor de rutinas**: se mantiene presionada la
  fila y se arrastra (en Flutter bastaba arrastrar desde el asa). Para quitar
  un ejercicio, además de deslizar a la izquierda, cada fila tiene una ✕.
- **Bluetooth apagado o sin permiso**: iOS no deja encenderlo desde la app; la
  pantalla de conexión lo dice en vez de mostrar el error técnico.
- Acceso con Google y recuperar contraseña siguen sin estar disponibles, igual
  que en Flutter.
- **Ficha del ejercicio**: muestra la animación y los pasos de "Cómo hacerlo"
  directamente, en lugar del botón "Ver tutorial" que en Flutter abría una
  pantalla aparte con un reproductor de video de muestra.
