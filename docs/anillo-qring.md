# Anillo QRing: lo que hace su app (para reemplazarla con Alma)

Tomado de 32 capturas de la app QRing (28 oct 2026). Anillo **R08_8105**, firmware **3.10.46**.

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
