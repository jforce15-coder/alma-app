# Anillo QRing: lo que hace su app (para reemplazarla con Alma)

Tomado de 32 capturas de la app QRing (28 oct 2026). Anillo **R08_8105**, firmware **3.10.46** (el 16-nov-2026 ya traía **3.10.48**).

## Lo que mide y muestra

| Medida | En la app QRing | Ajuste en el anillo | De dónde sale |
|---|---|---|---|
| Ritmo cardíaco | Gráfica del día, promedio, mín., máx., medición en vivo, zonas (calentamiento, quema de grasa, aeróbico, anaeróbico, límite) | Automático: activo y cada 15 min | Anillo (historial + en vivo). Las zonas las calcula la app |
| Oxígeno en sangre | Puntos por hora, promedio, mín., máx., en vivo; reparto <95 / 95–97 / ≥98 % | Automático: cada hora | Anillo |
| Estrés | Barras cada 30 min, promedio, mín., máx., en vivo; Relax 0–29, Normal 30–59, Medio 60–79, Alto 80–100 | Automático: cada 30 min | Anillo |
| HRV | Puntos cada hora, promedio, mín., máx., en vivo; Bajo <30, Normal 30–60, Bueno 61–101, Excelente >101 | Automático: cada hora | Anillo |
| Temperatura | Gráfica del día, promedio, mín., máx., en vivo | Automático: cada 30 min | Anillo |
| Actividad | Pasos, km, kcal por hora; metas 10 000 pasos / 5 km / 800 kcal; puntaje 0–100 | Metas | Anillo (por cuartos de hora); el puntaje lo calcula la app |
| Sueño | Horario, duración, fases (despierto, REM, ligero, profundo), eficiencia, minutos para dormirse, puntaje 0–100; ritmo, oxígeno, HRV y temperatura durante el sueño; constancia semanal | — | Anillo (fases); el puntaje lo calcula la app |
| Ejercicio (Sport Record) | Tipo (Boxing), duración, kcal, ritmo promedio y máximo, gráfica, zonas; resumen por día, semana y mes; botón «GO!» para empezar | — | Se inicia desde la app; el anillo mide el ritmo |

Inicio de Health: tarjetas (Activity, Sleep, Heart Rate, Sport Record, Body temperature, HRV, Blood Oxygen, Stress) con «Edit card» para ordenarlas.

## Ajustes del anillo (pestaña «Me»)

- Datos del anillo: nombre, dirección, firmware, conectado, batería, «Unbind».
- **Touch Control** (gasta más batería): se duerme tras **Sleep Duration** (3 min); se despierta con **doble toque**. Modos:
  - **Music**: toque = pausa/reproducir; deslizar = canción anterior/siguiente.
  - **Short Video** (el que se usa hoy): toque = pausa; deslizar = video anterior/siguiente; doble toque = like.
  - **EBook**: deslizar = página anterior/siguiente.
  - **Tasbih**: contador de toques. **No lo usamos** (decisión de Juan): Alma no lo ofrece.
  - **Take Photo**: abre la cámara; mantener = foto.
  - **Turn off**.
- Take Pictures, Touch Guide (6 pasos), Find device.
- Health Monitoring: ritmo (15 min), oxígeno (cada hora), estrés (30 min), HRV (cada hora), temperatura (30 min); cada uno con interruptor.
- Health reminder, Notifications, Call Notification, Ring Game, Theme Style.
- Unidades (métrico), temperatura (°C), aviso de batería baja, Apple Health, actualización de firmware, ajustes del sistema.

## Para los toques con el teléfono bloqueado

1. **Music**: el anillo actúa como control multimedia; iOS manda «reproducir/pausa» a la app que tiene el audio aun bloqueado. Alma queda como la app de audio activa y el toque la llama.
2. **Avisos por Bluetooth**: la prueba de toques en Health muestra si el anillo manda algo por su canal de datos al tocarlo (en el modo que tenga puesto); si lo hace, Alma lo oye aunque el teléfono esté bloqueado.
3. Respaldo: Siri, botón de Acción, control en la pantalla de bloqueo.

## Lo que Alma ya maneja (rebanada 2, 16-nov-2026)

`AnilloAlma.swift` (herramientas de la voz y la pantalla Dispositivos) y `AnilloDatos.swift` (lectura pura, probada en `Pruebas/AnilloDatos`).

| Herramienta de la voz | Comando | Qué contesta |
|---|---|---|
| `anillo_estado` (con `mostrar` abre Dispositivos) | `0x03` | conectado, batería y si carga, firmware (servicio 180A, 2A26), última sincronización |
| `anillo_medidas` (día 0–6) | `0x43` pasos · `0x15` historial del ritmo | pasos, kcal, km; ritmo del día (mín., máx., promedio, la última con su hora); último ritmo y oxígeno en vivo |
| `anillo_medir_ahora` (ritmo u oxígeno, `cancelar`) | `0x69` y `0x6A` para parar | el valor tras 3 lecturas buenas del ritmo (2 del oxígeno) o la última buena a los 30 s |
| `anillo_ajustes` (ver o cambiar) | `0x16 01` leer · `0x16 02` guardar | monitoreo del ritmo: encendido y cada cuántos minutos (5 a 60) |
| `anillo_buscar` | `0x10` | el anillo parpadea |

- Sin conexión, cada herramienta lo dice (`conectado: false`) y da lo último leído con su hora; nunca inventa.
- La ficha de la llamada lleva «ANILLO DE JUAN (QRing): conectado · batería 64 % (hace 5 min)…» solo si hay un anillo guardado.
- La app manda la Lectura del anillo al Hub como mucho cada 10 min (`anilloResumen` → `ANILLO_RES_<clave>`): solo números con su hora,
  sin nombre ni dirección del anillo. Por WhatsApp, chat o teléfono Alma la dice con la herramienta `anillo` del chat.
- Al conectar se leen los pasos y el ritmo de hoy (como mucho cada 30 min).

Paquetes que se leen (byte 0 = comando, byte 15 = suma):
- Batería `03 nivel carga`. Ajustes del ritmo `16 01 activo(1/2) minutos`. En vivo `69 tipo(1 ritmo · 3 oxígeno) error valor` (valor 0 = todavía mide).
- Pasos `43 F0 … b3` (b3 = 1: kcal en decenas) · `43 año mes día cuarto índice total kcal(2) pasos(2) metros(2)` · `43 FF` sin datos.
- Historial del ritmo `15 00 paquetes minutos` · `15 01 hora(4) 9 valores` · `15 nn 13 valores` · `15 FF` sin datos.

**Por confirmar contra la app QRing:** las kcal (con el protocolo nuevo vienen en decenas; si la suma del día pasa de 20 000 se toma
como calorías y se pasa a kcal) y el oxígeno automático (por ahora solo el medido en vivo). El estrés, el HRV, la temperatura y el sueño
todavía no tienen comando conocido.

## Diagnóstico Bluetooth y los toques (16-nov-2026)

El robot (`anillo`, campo `ble`) todavía **no tiene ningún diagnóstico**: Juan no ha corrido «Diagnóstico del anillo (Bluetooth)». Falta
saber qué llega por el canal de datos al tocar el anillo en modo Music y Short Video. El cambio de modo (Touch Control) no se implementa:
su comando no se conoce.

## Los lentes (iTOUCH AURA, sin cámara)

Bluetooth 6.0, dos baterías de 110 mAh (una por patilla), carga magnética, música 4–6 h, llamadas 3–4 h. Son audífonos Bluetooth
clásicos (A2DP/HFP): **iOS no da su batería a las apps** (solo al widget de Baterías). Lo que sí se sabe (`Lentes.swift`): si están
conectados (salida de audio o micrófono Bluetooth con «AURA»/«iTOUCH» en el nombre) y si son la salida de ahora. Si algún día se
anuncian por Bluetooth de baja energía con el servicio 180F, la pantalla Dispositivos lee su batería; si no, dice «no disponible».
La salida de audio la elige Juan con el botón de iOS (las apps no pueden cambiarla solas).
