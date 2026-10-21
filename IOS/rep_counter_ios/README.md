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
  Workout/    WorkoutController: series, descanso, calibración
  Theme/      colores, tipografía, íconos SVG, formato de números y fechas
  Widgets/    botones, campos, chips, gráfica, diálogos y hojas
  Screens/    todas las pantallas
  Resources/Fonts/  Barlow (licencia OFL)
```

Cada archivo Swift corresponde a uno o varios `.dart` de `rep_counter_app/lib`
con los mismos nombres de tipos y funciones, para que un cambio en una versión
sea fácil de llevar a la otra.

## Catálogo de ejercicios e imágenes

191 ejercicios: los 32 originales más 159 elegidos del dataset abierto
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
- **Los otros 21**, sin equivalente fiel ahí, usan la animación del dataset
  (`Resources/ExerciseAnimations/<id>.gif`). Esa animación mide 180×180 y su
  licencia prohíbe distribuirla a más resolución, así que se muestra a 200 pt
  como máximo.

Todo va dentro de la app, así que funciona sin internet.

- La lista curada está en `tools/catalog/curated.py`. `generate.py` (con la
  ruta de un clon del dataset como argumento) regenera la migración
  `rep_counter_api/db/migrations/003_dataset_exercises.sql`, el catálogo semilla
  `Resources/Catalog/catalog.json`, las miniaturas, las fotos y las
  animaciones (descarga las fotos la primera vez). Para agregar más
  ejercicios después, usa una migración nueva (`004_...`), no reescribas la 003
  si ya se aplicó en producción.
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
- iOS guarda en caché los servicios de cada dispositivo. Si después de cargar
  el firmware nuevo no aparece la batería, olvida el sensor en Ajustes →
  Bluetooth o apaga y prende el Bluetooth.

## Sensor sobre la pila de pesas

En los 29 ejercicios de polea y las 17 máquinas de selector (se cambia el
pasador, no discos: pec deck, jalones, extensión de piernas…) el sensor va
encima de la pila, pegado a la placa superior. La pila sube y baja sin girar,
así que esos ejercicios usan el perfil 2 del firmware, que cuenta por
velocidad vertical en lugar de inclinación. En el contador se ve hacia dónde va
la pila y a qué velocidad, en vez de la barra de ángulo.

- Si no se puede pegar arriba, sirve de costado en la placa superior (o en
  cualquiera por encima del pasador): el algoritmo aprende la vertical al
  calibrar, así que la orientación da igual. Lo que no tolera es que se
  deslice: en simulación, hasta 2–3° no pasa nada y desde 4° pierde
  repeticiones lentas. La ficha del ejercicio lo explica y el dibujo marca la
  posición alternativa.
- La lista está en `tools/catalog/curated.py` (`SELECTOR_MACHINES`; las poleas
  entran todas) y llega al servidor con la migración 004.
- Las máquinas de discos (prensa, hack, remo en T, remo alto, Smith, talones)
  no tienen pila y siguen como antes.
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
  fila y se arrastra (en Flutter bastaba arrastrar desde el asa). Deslizar a la
  izquierda para eliminar funciona igual.
- **Bluetooth apagado o sin permiso**: iOS no deja encenderlo desde la app; la
  pantalla de conexión lo dice en vez de mostrar el error técnico.
- Acceso con Google y recuperar contraseña siguen sin estar disponibles, igual
  que en Flutter.
- **Ficha del ejercicio**: muestra la animación y los pasos de "Cómo hacerlo"
  directamente, en lugar del botón "Ver tutorial" que en Flutter abría una
  pantalla aparte con un reproductor de video de muestra.
