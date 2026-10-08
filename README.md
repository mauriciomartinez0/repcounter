# Rep Counter

Contador de repeticiones con un sensor XIAO nRF52840 Sense. La placa cuenta;
el teléfono elige el ejercicio, muestra el conteo y guarda el historial.

| Carpeta | Qué es |
|---|---|
| [`rep_counter_ble/`](rep_counter_ble/) | Firmware de la placa (Arduino). Cuenta repeticiones y las publica por Bluetooth LE. |
| [`rep_counter_app/`](rep_counter_app/) | App en Flutter: cuenta, rutinas, catálogo, entrenamiento e historial. |
| [`rep_counter_api/`](rep_counter_api/) | Backend en FastAPI + PostgreSQL: cuentas, catálogo, rutinas y sesiones, pensado para uso sin conexión. |

Cada carpeta tiene su README con cómo correrla y lo que falta.
