/* Aparición al entrar en pantalla.
 *
 * Vive en un archivo y no en línea porque la CSP del sitio no permite
 * `unsafe-inline` en script-src: pegado dentro del HTML el navegador lo
 * bloquea sin ejecutarlo, y el único síntoma es un error en la consola.
 */
// Aparición al entrar en pantalla.
  //
  // IntersectionObserver y no un listener de scroll: ese último corre en cada
  // cuadro, no se agrupa, y traba el desplazamiento justo en los teléfonos
  // modestos que son la mayoría del público.
  //
  // La animación está motivada: revela el contenido en el orden en que se lee,
  // que es la única razón válida para animar algo en una página de conversión.
  (function () {
    var objetivos = document.querySelectorAll('.revelar');
    var reducido = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    if (reducido || !('IntersectionObserver' in window)) {
      objetivos.forEach(function (el) { el.classList.add('visible'); });
      return;
    }

    var obs = new IntersectionObserver(function (entradas) {
      entradas.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add('visible');
        obs.unobserve(e.target); // una sola vez: no se re-anima al volver
      });
    }, { threshold: 0.15, rootMargin: '0px 0px -8% 0px' });

    objetivos.forEach(function (el) { obs.observe(el); });

    // Plazo máximo. El umbral de 0.15 no se alcanza nunca para un elemento más
    // alto que la pantalla, y hay navegadores que no entregan la primera
    // notificación si la pestaña se abrió en segundo plano. En cualquiera de
    // esos casos el visitante se queda mirando un hueco, así que a los tres
    // segundos se muestra todo lo que siga escondido, animación o no.
    setTimeout(function () {
      document.querySelectorAll('.revelar:not(.visible)')
        .forEach(function (el) { el.classList.add('visible'); });
      obs.disconnect();
    }, 3000);
  })();
