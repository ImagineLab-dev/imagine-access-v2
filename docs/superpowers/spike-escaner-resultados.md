# Spike del escáner — resultados

**Estado:** PENDIENTE — requiere dos teléfonos físicos.
**Build servido:** `--profile`, con credenciales reales.

Este documento decide si "paridad total con escáner en puerta" —la primera decisión del
proyecto— se sostiene. Se completa con números medidos, no con impresiones.

---

## Cómo correrlo

El servidor ya está levantado en la máquina de desarrollo:

**URL para los teléfonos: `https://192.168.100.7:8443`**

Los teléfonos tienen que estar en la misma red Wi-Fi. Al abrir, el navegador va a avisar
que el certificado no es de confianza — es esperado, es un certificado autofirmado para
desarrollo. Hay que aceptar y continuar. **Sin HTTPS la cámara no abre**: `getUserMedia`
exige contexto seguro y una IP de LAN por HTTP no califica.

Abajo a la izquierda de la pantalla del escáner aparece un overlay verde con
`n / última / mediana / máximo` en milisegundos. De ahí salen los números.

Si el servidor se cayó, se relevanta con:

```bash
cd build/web && npx http-server -p 8000 --silent
npx local-ssl-proxy --source 8443 --target 8000 --hostname 0.0.0.0
```

## Códigos de prueba necesarios

1. Un ticket válido sin usar, **impreso en papel**
2. Ese mismo ticket **en la pantalla de otro teléfono**
3. Un ticket ya validado
4. Un ticket de otro evento
5. Un QR con texto arbitrario (por ejemplo `hola mundo`)

---

## Criterio de aceptación

**Detección por debajo de 1500 ms de forma consistente en iPhone.** Es el umbral donde el
escaneo deja de frenar una cola de gente en la puerta.

---

## Medición — iPhone / Safari

Modelo: `_______________`  ·  iOS: `_______________`

10 escaneos por fila.

| Condición | Mediana (ms) | Máx (ms) | Fallos de 10 |
|---|---|---|---|
| Papel, luz de interior buena | | | |
| Papel, luz baja | | | |
| Pantalla de teléfono, brillo alto | | | |
| Pantalla de teléfono, brillo bajo | | | |

## Medición — Android / Chrome

Modelo: `_______________`  ·  Android: `_______________`

| Condición | Mediana (ms) | Máx (ms) | Fallos de 10 |
|---|---|---|---|
| Papel, luz de interior buena | | | |
| Papel, luz baja | | | |
| Pantalla de teléfono, brillo alto | | | |
| Pantalla de teléfono, brillo bajo | | | |

---

## Matriz funcional

Anotar lo observado, no lo esperado. Los primeros cuatro casos son los que separan
"probé el happy path" de "está probado".

| Caso | iPhone/Safari | Android/Chrome |
|---|---|---|
| Ticket válido → acepta | | |
| Ticket ya usado → rechaza con el motivo correcto | | |
| Ticket de otro evento → rechaza | | |
| QR de texto arbitrario → error controlado, no crashea | | |
| Escaneo sin conexión → encola y avisa | | |
| Reconexión → la cola se procesa sola | | |

### Verificación aparte: sin CDN

En Chrome de escritorio, con DevTools → Network filtrando por `unpkg`, abrir `/scanner`.
**No debe aparecer ninguna request.** Si aparece, el ZXing self-hosteado de la Tarea 8 no
está tomando efecto.

Resultado: `_______________`

---

## Carga inicial

Caché vacía, throttling en Fast 4G.

| Métrica | Valor |
|---|---|
| Tiempo hasta pantalla de bienvenida interactiva | |
| Peso total transferido | |

Referencia: el `main.dart.js` de release pesa 4.9 MB sin comprimir. El de profile —el que
sirve este spike— pesa 14.7 MB, así que **este número va a ser peor que el de producción**.
Medir para tener orden de magnitud, no como cifra final.

---

## Veredicto

Marcar uno:

- [ ] **GO** — la mediana en iPhone está por debajo de 1500 ms en todas las condiciones y
  la matriz funcional pasa completa. Se escriben los planes 2 y 3 según el spec.
- [ ] **GO CON CONTINGENCIA** — el criterio se incumple solo con luz baja o desde pantalla.
  Se aplica la contingencia 1 del spec §4.2 (bajar resolución de video y recortar a un ROI
  central) y se vuelve a medir antes de seguir.
- [ ] **NO GO** — el criterio se incumple de forma amplia. Se escala a la contingencia 2:
  shim de `dart:js_interop` a `zxing-wasm`. Es un plan aparte y hay que estimarlo.

Notas:

```
```
