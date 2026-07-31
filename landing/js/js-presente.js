/* Marca en el <html> que hay JavaScript disponible.
 *
 * El estado oculto de `.revelar` está condicionado a la clase `.js`. Sin esta
 * línea la clase nunca aparece, nada se esconde, y la página se ve completa
 * desde el primer cuadro: una landing no puede depender de un script para
 * mostrar el texto, y el modo de fallo de ese acoplamiento es la página en
 * blanco.
 *
 * Es un archivo y no un bloque en línea porque la CSP del sitio no permite
 * `unsafe-inline` en script-src. La etiqueta va en el <head> SIN `async` ni
 * `defer` a propósito: así se ejecuta antes de que se pinte el primer cuadro y
 * no se ve el contenido aparecer y volver a esconderse.
 */
document.documentElement.className += ' js';
