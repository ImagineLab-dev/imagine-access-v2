/**
 * Pruebas de la extracción de la IP del cliente.
 *
 * Se corre con Node 24, que ejecuta TypeScript sin compilar:
 *
 *     node supabase/functions/_shared/rate_limiter.test.ts
 *
 * No usa Deno a propósito: así se puede correr desde cualquier máquina de
 * desarrollo sin instalar nada. El módulo no importa nada, y `Request` es una
 * API web que Node trae desde la 18.
 *
 * DE DÓNDE SALEN LOS CASOS
 *
 * No están inventados: la forma de la cadena se midió contra producción el
 * 06/08/2026 instrumentando `meta_evento` y mirando los logs.
 *
 *     sin falsificar   ->  "72.60.51.162, 10.11.84.6"
 *     falsificando     ->  "8.8.8.8, 72.60.51.162, 10.11.84.6"
 *
 * `10.11.84.6` es Traefik. Traefik AGREGA la dirección real detrás de lo que
 * mandó el cliente en vez de reemplazarla, así que leer el primer elemento
 * —que es lo que se hacía— devuelve lo que el atacante quiso.
 */

import { getClientIp, ipObservada, ipParaMeta, isRateLimited } from './rate_limiter.ts'

function pedido(cabeceras: Record<string, string>): Request {
    return new Request('https://api.imaginecloud.digital/functions/v1/meta_evento', {
        method: 'POST',
        headers: cabeceras,
    })
}

let ok = 0
let mal = 0

function comprobar(titulo: string, obtenido: unknown, esperado: unknown) {
    if (obtenido === esperado) {
        ok++
        console.log(`  ok   ${titulo}`)
    } else {
        mal++
        console.log(`  MAL  ${titulo}`)
        console.log(`         obtenido ${JSON.stringify(obtenido)}, esperado ${JSON.stringify(esperado)}`)
    }
}

console.log('\n=== tráfico legítimo, sin nadie falsificando ===')
comprobar('cliente IPv4 real',
    ipObservada(pedido({ 'x-forwarded-for': '72.60.51.162, 10.11.84.6' })), '72.60.51.162')
comprobar('cliente IPv6 real',
    ipObservada(pedido({ 'x-forwarded-for': '2a02:4780:66:5e49::1, 10.11.84.6' })), '2a02:4780:66:5e49::1')
comprobar('IPv6 de un móvil argentino',
    ipObservada(pedido({ 'x-forwarded-for': '2800:810:512:abc::1, 10.11.84.6' })), '2800:810:512:abc::1')
comprobar('espacios de más alrededor de las comas',
    ipObservada(pedido({ 'x-forwarded-for': '  72.60.51.162 ,  10.11.84.6  ' })), '72.60.51.162')

console.log('\n=== falsificación: lo que motivó el arreglo ===')
comprobar('XFF falso IPv4 (medido en producción)',
    ipObservada(pedido({ 'x-forwarded-for': '8.8.8.8, 72.60.51.162, 10.11.84.6' })), '72.60.51.162')
comprobar('XFF falso IPv6 (medido en producción)',
    ipObservada(pedido({ 'x-forwarded-for': '2001:4860:4860::8888, 72.60.51.162, 10.11.84.6' })), '72.60.51.162')
comprobar('varias falsas encadenadas',
    ipObservada(pedido({ 'x-forwarded-for': '1.1.1.1, 2.2.2.2, 3.3.3.3, 72.60.51.162, 10.11.84.6' })), '72.60.51.162')
comprobar('mete internas para cortar la lectura desde la derecha',
    ipObservada(pedido({ 'x-forwarded-for': '8.8.8.8, 10.0.0.1, 72.60.51.162, 10.11.84.6' })), '72.60.51.162')
comprobar('solo internas falsas antes de la real',
    ipObservada(pedido({ 'x-forwarded-for': '10.0.0.1, 192.168.1.1, 72.60.51.162, 10.11.84.6' })), '72.60.51.162')
comprobar('X-Real-IP falsa con XFF presente',
    ipObservada(pedido({ 'x-forwarded-for': '72.60.51.162, 10.11.84.6', 'x-real-ip': '1.2.3.4' })), '72.60.51.162')

console.log('\n=== límite conocido: desde adentro del servidor sí se puede falsear ===')
// Este caso se midió: un curl hecho en el propio VPS sale por el bridge de
// Docker, así que Traefik escribe `172.18.0.1` —privada— y la lectura sigue
// hasta lo que mandó el cliente. Está documentado en `ipObservada` por qué se
// acepta: cerrarlo obliga a leer una posición fija, y eso rompe feo si alguien
// agrega un proxy interno. Se prueba para que quede explícito, no por deseable.
comprobar('desde adentro, con falsa adelante, gana la falsa (aceptado)',
    ipObservada(pedido({ 'x-forwarded-for': '8.8.8.8, 172.18.0.1, 10.11.84.6' })), '8.8.8.8')
comprobar('desde afuera, con falsa adelante, NO gana la falsa',
    ipObservada(pedido({ 'x-forwarded-for': '8.8.8.8, 72.60.51.162, 10.11.84.6' })), '72.60.51.162')

console.log('\n=== direcciones de la propia infraestructura ===')
comprobar('solo Traefik', ipObservada(pedido({ 'x-forwarded-for': '10.11.84.6' })), null)
comprobar('bridge de Docker', ipObservada(pedido({ 'x-forwarded-for': '172.18.0.1, 10.11.84.6' })), null)
comprobar('red de Kong', ipObservada(pedido({ 'x-forwarded-for': '172.19.0.10, 10.11.84.6' })), null)
comprobar('loopback', ipObservada(pedido({ 'x-forwarded-for': '127.0.0.1' })), null)
comprobar('loopback IPv6', ipObservada(pedido({ 'x-forwarded-for': '::1, 10.11.84.6' })), null)
comprobar('ULA IPv6 (fc00::/7)', ipObservada(pedido({ 'x-forwarded-for': 'fd12:3456::1, 10.11.84.6' })), null)
comprobar('link-local IPv6 (fe80::/10)', ipObservada(pedido({ 'x-forwarded-for': 'fe80::1, 10.11.84.6' })), null)
comprobar('link-local IPv4', ipObservada(pedido({ 'x-forwarded-for': '169.254.1.1, 10.11.84.6' })), null)

console.log('\n=== bordes del rango privado 172.16/12: los vecinos SON públicos ===')
comprobar('172.15.0.1 es pública', ipObservada(pedido({ 'x-forwarded-for': '172.15.0.1, 10.11.84.6' })), '172.15.0.1')
comprobar('172.16.0.1 es privada', ipObservada(pedido({ 'x-forwarded-for': '172.16.0.1, 10.11.84.6' })), null)
comprobar('172.31.0.1 es privada', ipObservada(pedido({ 'x-forwarded-for': '172.31.0.1, 10.11.84.6' })), null)
comprobar('172.32.0.1 es pública', ipObservada(pedido({ 'x-forwarded-for': '172.32.0.1, 10.11.84.6' })), '172.32.0.1')

console.log('\n=== formas raras: corchetes y puertos ===')
comprobar('IPv6 entre corchetes con puerto',
    ipObservada(pedido({ 'x-forwarded-for': '[2a02:4780:66:5e49::1]:443, 10.11.84.6' })), '2a02:4780:66:5e49::1')
comprobar('IPv6 entre corchetes sin puerto',
    ipObservada(pedido({ 'x-forwarded-for': '[2a02:4780:66:5e49::1], 10.11.84.6' })), '2a02:4780:66:5e49::1')
comprobar('IPv4 con puerto',
    ipObservada(pedido({ 'x-forwarded-for': '72.60.51.162:54321, 10.11.84.6' })), '72.60.51.162')

console.log('\n=== sin XFF, ahí X-Real-IP sí la escribe Traefik ===')
comprobar('X-Real-IP pública', ipObservada(pedido({ 'x-real-ip': '72.60.51.162' })), '72.60.51.162')
comprobar('X-Real-IP interna', ipObservada(pedido({ 'x-real-ip': '10.11.84.6' })), null)
comprobar('sin ninguna cabecera', ipObservada(pedido({})), null)
comprobar('XFF vacía cae a X-Real-IP',
    ipObservada(pedido({ 'x-forwarded-for': '', 'x-real-ip': '72.60.51.162' })), '72.60.51.162')

console.log('\n=== getClientIp: el cubo del limitador nunca es null ===')
comprobar('cliente real', getClientIp(pedido({ 'x-forwarded-for': '72.60.51.162, 10.11.84.6' })), '72.60.51.162')
comprobar('el falsificador cae en el cubo de su IP real',
    getClientIp(pedido({ 'x-forwarded-for': '8.8.8.8, 72.60.51.162, 10.11.84.6' })), '72.60.51.162')
comprobar("sin nada -> 'unknown'", getClientIp(pedido({})), 'unknown')

console.log('\n=== ipParaMeta ===')
comprobar('IPv6 del visitante',
    ipParaMeta(pedido({ 'x-forwarded-for': '2800:810:512:abc::1, 10.11.84.6' })), '2800:810:512:abc::1')
comprobar('IPv4 del visitante',
    ipParaMeta(pedido({ 'x-forwarded-for': '72.60.51.162, 10.11.84.6' })), '72.60.51.162')
comprobar('nunca la falsificada',
    ipParaMeta(pedido({ 'x-forwarded-for': '8.8.8.8, 72.60.51.162, 10.11.84.6' })), '72.60.51.162')
comprobar("null, no 'unknown', cuando no hay nada", ipParaMeta(pedido({})), null)
comprobar('null cuando solo hay infraestructura',
    ipParaMeta(pedido({ 'x-forwarded-for': '172.18.0.1, 10.11.84.6' })), null)
comprobar('basura no numérica -> null',
    ipParaMeta(pedido({ 'x-forwarded-for': 'no-soy-una-ip, 10.11.84.6' })), null)

console.log('\n=== el limitador en sí sigue funcionando ===')
const cubo = `prueba:${Math.random()}`
let bloqueos = 0
for (let i = 0; i < 5; i++) if (isRateLimited(cubo, 3, 60_000)) bloqueos++
comprobar('de 5 pedidos con tope 3, se bloquean 2', bloqueos, 2)
comprobar('otra IP no arrastra el bloqueo', isRateLimited(`prueba:${Math.random()}`, 3, 60_000), false)

console.log(`\n${'='.repeat(48)}\n  ${ok} pasaron, ${mal} fallaron\n${'='.repeat(48)}`)
process.exit(mal === 0 ? 0 : 1)
