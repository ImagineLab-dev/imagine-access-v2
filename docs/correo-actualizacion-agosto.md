# Correo de actualización — agosto 2026

Aviso a los clientes sobre el rediseño y las correcciones del 05/08/2026.

## A quién va

Cuatro cuentas reales, todas con acceso de administrador y menos de una semana
de antigüedad. Ninguna llegó todavía a usar el sistema en un evento con público.

**Los nombres y las direcciones no se escriben acá.** Son datos de terceros y
este repositorio no es lugar para ellos; además estuvo público hasta el
06/08/2026, que es exactamente por qué se sacaron. La lista se saca de la base
en el momento de enviar:

```sql
SELECT p.email, p.full_name, o.name AS organizacion,
       (SELECT count(*) FROM events e WHERE e.organization_id = o.id) AS eventos
FROM users_profile p
JOIN organizations o ON o.id = p.organization_id
WHERE p.role = 'admin'
  AND o.name NOT IN ('SONICO')      -- las cuentas propias no son destinatarios
ORDER BY p.created_at;
```

Una de las cuatro cuentas **no creó ningún evento todavía**. Vale la pena
mandarle el mismo correo —la novedad le sirve igual— pero es la única a la que
conviene escribirle aparte después si no responde: alguien que se registró y
nunca creó nada se trabó en algún lado, y eso se pregunta, no se adivina.

## Sobre el idioma

Los destinatarios están en Uruguay, Argentina y Perú. El voseo suena natural en
los dos primeros y ajeno en el tercero, así que el texto evita a propósito las
formas que obligan a elegir: dice "vale la pena probarlo" en vez de
"probalo/pruébalo". No es un detalle menor cuando son cuatro personas y cada
una nota si le hablan raro.

## Asunto

> Imagine Access cambió bastante — y el escáner ahora vuela

Alternativas probadas y descartadas:

- *"Novedades de Imagine Access"* — no dice nada, parece boletín.
- *"¡Grandes noticias!"* — huele a spam y no informa.
- *"Actualización v2.0"* — a un organizador de eventos no le importa el número
  de versión.

## Qué NO dice el correo, a propósito

- No enumera las veinte correcciones. Se eligieron cuatro; el resto se descubre
  usando.
- No menciona nada técnico —el decodificador, el service worker, el contraste—.
  Se cuenta el efecto, no la causa.
- No pide "feedback" en abstracto. Pide una cosa concreta: que abran el escáner
  y prueben un ticket.

## Texto plano

```
Hola {{nombre}},

Estuvimos varios días trabajando en Imagine Access y quedó bastante distinto
a lo que viste cuando te registraste. Te cuento lo que más se nota.

EL ESCÁNER ES OTRA COSA
Ahora usa el lector de códigos del propio teléfono en vez de uno por software,
así que engancha el QR casi al instante, incluso con poca luz o el código
torcido. También corregimos un problema por el que a veces había que cerrar y
volver a abrir la app para que leyera.

CUANDO UNA ENTRADA YA SE USÓ, TE DICE A QUÉ HORA ENTRÓ
Antes un código repetido se veía igual que uno falso. Ahora son dos pantallas
distintas: la repetida es ámbar y muestra la hora del primer ingreso. En la
puerta eso es la diferencia entre discutir a ciegas y saber qué pasó.

LOS PRECIOS SE VEN EN LA MONEDA DE TU EVENTO
Había un error por el que los importes se mostraban en guaraníes aunque el
evento estuviera en otra moneda. Si alguna vez viste un precio raro, era eso.
Ya está corregido.

TODO SE ALCANZA DESDE ABAJO
Panel, eventos, escáner y tickets ahora están en una barra fija. Durante un
evento no tenés que buscar nada en un menú.

Además la app se actualiza sola: no vas a tener que hacer nada para recibir lo
que venga.

------------------------------------------------------------------
Lo que te pido: entrá y emití un ticket de prueba a tu propio correo, abrí el
PDF en otra pantalla y escanealo. Son dos minutos y es exactamente lo que va a
pasar la noche del evento.

    https://imaginecloud.digital

Si algo no funciona o se ve raro, respondé este correo y lo miro. Sos de los
primeros en usarlo y lo que reportes se arregla rápido.

Patricio
Imagine Access
```

## Instrucciones de envío

Cuatro correos, uno por persona, con `{{nombre}}` reemplazado. **No en copia
oculta a los cuatro**: son cuatro clientes tempranos, y un correo que parece
enviado a una lista invita a no contestar. La respuesta es justamente lo que se
busca.

Enviar desde `tickets@imaginecloud.digital`, que es la dirección con SPF y DKIM
configurados del dominio —la misma por la que salen los códigos de
confirmación—. Desde una cuenta personal de Gmail hay riesgo de que caiga en
spam.
