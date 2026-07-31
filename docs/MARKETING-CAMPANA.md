# Campaña Imagine Access — imágenes, copys y locuciones

Material para generar 8 piezas con Nano Banana a partir de capturas reales de
la app, con su texto y su guion de voz en off para ElevenLabs.

**Regla que atraviesa todo:** solo se promete lo que el producto hace hoy y
está verificado. La lista de lo que NO hay que afirmar está al final.

---

## Cómo prompteá a Nano Banana con capturas

El modelo tiende a "mejorar" la interfaz: te reescribe los botones, te inventa
palabras y te deja una captura que no existe. Tres cosas lo evitan.

**1. Exigí la preservación, siempre.** Cerrá cada prompt con esta línea:

> `Do not alter, redraw, retype or restyle anything inside the phone screen. The screenshot must be reproduced pixel-for-pixel, including all Spanish text, icons and colors. Only generate what surrounds the device.`

**2. Subí la captura ya recortada** al tamaño del dispositivo que querés. Si le
das una captura de escritorio y le pedís un teléfono, va a reinterpretar el
diseño en vez de encajarlo.

**3. Pedí luz coherente.** Si la escena es un boliche oscuro, decile que la
pantalla es la fuente de luz principal sobre la mano y la cara. Sin eso, el
teléfono queda pegoteado como un sticker.

**Paleta de marca:** fondo `#0B0F16`, acento azul neón `#4A9EFF`. Repetila en
cada prompt para que las 8 piezas se vean de la misma familia.

**Formatos:** 9:16 para historias y Reels, 1:1 para el feed, 16:9 para YouTube y
la web.

---

## Pieza 1 — La puerta

**Captura a usar:** el escáner activo, con el visor abierto.

### Prompt

```
Photorealistic vertical shot, 9:16, of a young event staff member at the entrance
of a nightclub at night, holding a smartphone at chest height and scanning a
paper ticket held by a guest. The phone screen is the dominant light source: cool
blue #4A9EFF light spills onto both hands and the staff member's face and chest.
Background: a slightly out-of-focus queue behind a velvet rope, warm amber
streetlights, dark blue-black night air (#0B0F16). Shallow depth of field, 50mm
lens, cinematic color grade, subtle film grain. The phone is angled toward camera
so the screen is fully readable.

Do not alter, redraw, retype or restyle anything inside the phone screen. The
screenshot must be reproduced pixel-for-pixel, including all Spanish text, icons
and colors. Only generate what surrounds the device.
```

### Copy

> **La fila avanza o la fila se queja.**
>
> Escaneás, suena, entra. Sin planillas, sin buscar nombres en un papel, sin
> discutir en la puerta.
>
> Imagine Access — control de acceso para eventos de verdad.

### Guion para ElevenLabs (~14 s)

```
Todos vimos esa fila. La que no avanza.

El de la puerta buscando un nombre en una planilla mojada... mientras
cincuenta personas esperan afuera.

Escaneás. Suena. Entra.

Imagine Access.
```

---

## Pieza 2 — Sin internet

Es el diferencial más fuerte y el más fácil de explicar. Va segundo a propósito.

**Captura a usar:** el escáner con el aviso de modo sin conexión visible.

### Prompt

```
Photorealistic vertical shot, 9:16, of a hand holding a smartphone inside a
crowded warehouse party. The phone screen glows blue #4A9EFF and is perfectly
sharp; everything else is motion-blurred crowd, haze and colored stage light.
Top corner of the frame shows a phone status bar with NO signal bars — this
detail must be clearly visible. Dark background (#0B0F16), volumetric fog,
backlit silhouettes, cinematic grade, shallow depth of field.

Do not alter, redraw, retype or restyle anything inside the phone screen. The
screenshot must be reproduced pixel-for-pixel, including all Spanish text, icons
and colors. Only generate what surrounds the device.
```

### Copy

> **Se cayó el wifi. La puerta no.**
>
> Imagine Access sigue validando sin señal. Cuando vuelve la conexión, todo se
> sincroniza solo.
>
> Porque en un galpón lleno, el internet es lo primero que se cae.

### Guion para ElevenLabs (~16 s)

```
Galpón lleno. Dos mil personas. Y el wifi... se cae.

Con cualquier otro sistema, ahí se termina la noche.

Imagine Access sigue validando sin señal. Y cuando vuelve la conexión,
sincroniza todo solo.

Tu puerta no depende de la antena.
```

---

## Pieza 3 — Se instala sin tienda de apps

**Captura a usar:** el aviso de instalación, o la app ya en la pantalla de inicio
junto a otros íconos.

### Prompt

```
Photorealistic close-up, 1:1, of a smartphone home screen held in one hand,
where the Imagine Access icon sits among ordinary everyday app icons. A finger
is mid-gesture, about to tap it. Soft natural window light from the left, clean
neutral background, slight bokeh. Modern, calm, premium look. The composition
makes the icon feel completely native to the phone.

Do not alter, redraw, retype or restyle anything inside the phone screen. The
screenshot must be reproduced pixel-for-pixel, including all Spanish text, icons
and colors. Only generate what surrounds the device.
```

### Copy

> **Sin App Store. Sin Play Store. Sin esperar aprobaciones.**
>
> Se instala desde el navegador en veinte segundos y queda en la pantalla de
> inicio como cualquier otra app.
>
> Le pasás el link a tu equipo y ya están adentro.

### Guion para ElevenLabs (~15 s)

```
Contratás gente para la puerta el jueves. El evento es el sábado.

¿Vas a pedirle a cada uno que se cree una cuenta, busque en la tienda,
descargue, actualice?

Les pasás un link. Veinte segundos. Ya lo tienen en la pantalla de inicio.
```

---

## Pieza 4 — El QR no se puede repetir

**Captura a usar:** la pantalla de "ACCESO DENEGADO" o "YA USADO", en rojo.

### Prompt

```
Photorealistic vertical shot, 9:16, dramatic and tense: a phone held by a
doorperson, its screen washing intense red light across their forearm and jaw.
In the blurred background, a guest's silhouette caught mid-step. Night club
entrance, dark blue-black (#0B0F16), hard rim light from behind. High contrast,
cinematic, slight handheld feel, 35mm lens.

Do not alter, redraw, retype or restyle anything inside the phone screen. The
screenshot must be reproduced pixel-for-pixel, including all Spanish text, icons
and colors. Only generate what surrounds the device.
```

### Copy

> **Un QR. Una entrada. Una vez.**
>
> Cada ticket va firmado. No se clona, no entra dos veces, y no sirve para otra
> fecha.
>
> La captura de pantalla que le mandaron por WhatsApp no pasa.

### Guion para ElevenLabs (~17 s)

```
La entrada que compró uno... y le mandó por WhatsApp a tres amigos.

El primero entra. El segundo, no.

Cada QR va firmado y vale una sola vez. Y el de la fiesta del mes que viene
no te sirve para la de hoy.

Lo que perdés en colados, lo ganás en la puerta.
```

---

## Pieza 5 — Todo en vivo

**Captura a usar:** el panel de control con métricas.

### Prompt

```
Photorealistic 16:9 shot from behind and slightly above: a promoter leaning on
a production desk in a dim backstage area, looking at a tablet propped on a
stand. The tablet screen is bright and fully legible. On the desk: a walkie
talkie, a coffee cup, a roll of wristbands. Through a doorway in the far
background, blurred stage lights and crowd. Moody, cinematic, teal and amber
color grade, dark base (#0B0F16).

Do not alter, redraw, retype or restyle anything inside the tablet screen. The
screenshot must be reproduced pixel-for-pixel, including all Spanish text, icons
and colors. Only generate what surrounds the device.
```

### Copy

> **Cuántos entraron. Quién vendió. Cuánto falta.**
>
> En vivo, mientras pasa. No al día siguiente cuando ya no podés hacer nada.
>
> Decidís con datos, no con la sensación de que "parece que hay poca gente".

### Guion para ElevenLabs (~16 s)

```
Once de la noche. ¿Cuánta gente entró?

"Y... parece que está flojo."

Parece no es un número.

Cuántos entraron, quién los vendió, cuánto falta para el aforo. En vivo,
mientras pasa. Cuando todavía podés hacer algo.
```

---

## Pieza 6 — Tu equipo, cada uno en lo suyo

**Captura a usar:** la gestión de equipo, o la vista de un RRPP con sus ventas.

### Prompt

```
Photorealistic 1:1 shot of three people at a nightclub entrance, each holding
their own phone, framed as a candid working moment — one checking a list, one
scanning, one talking to a guest off-frame. Warm practical lights overhead,
dark blue night background (#0B0F16), blue #4A9EFF screen glow on each face.
Documentary photography feel, natural expressions, 35mm, shallow depth of field.

Do not alter, redraw, retype or restyle anything inside any phone screen. Each
screenshot must be reproduced pixel-for-pixel, including all Spanish text, icons
and colors. Only generate what surrounds the devices.
```

### Copy

> **El RRPP vende. La puerta valida. Vos ves todo.**
>
> Cada uno entra con su acceso y ve solo lo que le corresponde.
>
> Se acabó pasarse el usuario del dueño por WhatsApp.

### Guion para ElevenLabs (~15 s)

```
¿Cuántas personas tienen hoy tu usuario y tu contraseña?

Con Imagine Access, cada uno tiene el suyo.

El RRPP vende y ve sus ventas. La puerta valida y ve la puerta. Vos ves todo.

Y cuando alguien deja de trabajar con vos, le sacás el acceso. Nada más.
```

---

## Pieza 7 — El ticket que recibe tu cliente

**Captura a usar:** el correo del ticket, con el arte del evento y el QR.

### Prompt

```
Photorealistic close-up, 4:5, of a person sitting on a couch at home looking at
an email on their phone, smiling slightly. The screen is fully legible and warm
against soft indoor evening light. Cozy blurred living room background, plant,
lamp. Intimate, aspirational, natural skin tones, 50mm, shallow depth of field.

Do not alter, redraw, retype or restyle anything inside the phone screen. The
screenshot must be reproduced pixel-for-pixel, including all Spanish text, icons
and colors. Only generate what surrounds the device.
```

### Copy

> **Tu flyer también viaja en el ticket.**
>
> El correo que recibe tu cliente lleva el arte de tu evento, sus datos y su QR.
> No una fila de texto plano.
>
> La experiencia empieza cuando compra, no cuando llega.

### Guion para ElevenLabs (~14 s)

```
Tu evento tiene un arte que pagaste, que aprobaste, que te encanta.

¿Y el ticket que recibe tu cliente? Una línea de texto y un código.

Con Imagine Access, el correo lleva tu arte, sus datos y su QR.

La experiencia empieza cuando compra.
```

---

## Pieza 8 — El precio

**Captura a usar:** la pantalla de suscripción con los planes.

### Prompt

```
Clean minimal product shot, 1:1: a smartphone floating at a slight angle against
a deep dark blue gradient background (#0B0F16), lit by a soft blue #4A9EFF rim
light from behind. Subtle reflection beneath the device. Lots of negative space
around it. Premium, calm, confident. Studio lighting, no props, no hands.

Do not alter, redraw, retype or restyle anything inside the phone screen. The
screenshot must be reproduced pixel-for-pixel, including all Spanish text, icons
and colors. Only generate what surrounds the device.
```

### Copy

> **25 dólares al mes. Eventos ilimitados.**
>
> Empezá con 15 tickets gratis. Sin tarjeta, sin llamada de ventas, sin
> contrato.
>
> Si un solo colado deja de entrar, ya se pagó.

### Guion para ElevenLabs (~15 s)

```
Veinticinco dólares al mes. Eventos ilimitados, tickets ilimitados, todo tu
equipo.

Arrancás con quince tickets gratis. Sin tarjeta y sin que te llame un vendedor.

Un colado que no entra ya te lo pagó.

Imagine Access. Probalo esta semana.
```

---

## ElevenLabs: cómo configurarlo

**Voz.** Buscá una masculina o femenina joven con acento rioplatense o neutro
latino. Evitá el castellano de España: para el público paraguayo y argentino
suena a doblaje y le baja credibilidad a todo.

**Parámetros de arranque:**

| Parámetro | Valor | Por qué |
|---|---|---|
| Stability | 40-50 | Más bajo da variación emocional; más alto lo vuelve plano y monótono |
| Similarity | 75 | Fiel a la voz sin sonar procesado |
| Style exaggeration | 0-20 | Arriba de eso empieza a sobreactuar |
| Speaker boost | activado | Mejor definición sobre música |

**Los puntos suspensivos son deliberados.** En los guiones marcan la pausa
donde cae el golpe. ElevenLabs los respeta. No los saques al copiar.

**Generá tres tomas de cada guion** y elegí. La misma configuración da lecturas
distintas, y la diferencia entre la primera y la mejor de tres es notoria.

**Mezcla.** La voz va unos 6 dB por encima de la música, y la música bajando
donde entra la locución. Sin eso, en el parlante de un teléfono no se entiende
nada — que es donde se va a escuchar el 90% de las veces.

---

## Lo que NO hay que prometer

Esto no es prudencia de más: una promesa que el producto no cumple se paga en
la puerta, delante de la gente.

**No digas "seguridad de nivel bancario"** ni nada parecido. Es una frase que
no significa nada y te expone a que alguien la audite.

**No digas "cero fraude" ni "imposible de falsificar".** Lo cierto y verificable
es que cada QR va firmado, vale una sola vez y no sirve para otro evento. Eso
ya es fuerte, y es defendible.

**No inventes clientes, cantidades ni testimonios.** "Usado en más de 500
eventos" es tentador y es exactamente el tipo de dato que alguien te va a pedir
que demuestres.

**No prometas soporte 24/7** hasta que exista alguien de guardia a las cuatro
de la mañana de un sábado, que es justo cuando se necesita.

**No muestres datos reales de compradores** en las capturas. Antes de generar
las imágenes, cargá tickets de prueba con nombres y correos inventados.
