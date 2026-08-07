/* Barra de acción fija al pie.
 *
 * POR QUÉ EXISTE
 *
 * El único llamado a la acción persistente de esta página estaba ARRIBA, en la
 * cabecera fija. En un teléfono eso es el borde superior de una pantalla de
 * seis pulgadas: el lugar más lejos del pulgar de alguien que sostiene el
 * aparato con una mano. Y medía 37px de alto, por debajo del mínimo de 44.
 *
 * Peor: entre el botón del hero y el de la sección de precio hay CINCO
 * secciones —el problema, cómo funciona, sin señal, las funciones— sin ninguna
 * salida a la acción. Es exactamente el tramo donde se construye la convicción,
 * y el visitante que se convencía a mitad de camino tenía que seguir bajando
 * hasta pasar el precio para poder actuar.
 *
 * DOS DECISIONES QUE NO SON OBVIAS
 *
 * 1. No aparece de entrada. Espera a que el hero salga de pantalla, porque
 *    mientras el hero se ve ya hay dos botones ahí: una barra fija encima sería
 *    un tercero compitiendo por la misma decisión.
 *
 * 2. Se esconde cuando llega el cierre. Esa sección TIENE su propio botón, y
 *    dejar la barra encima sería pedirle al visitante que elija entre dos
 *    llamados idénticos separados por 60 píxeles. Una barra fija que no sabe
 *    cuándo callarse es publicidad; una que se retira cuando el contenido toma
 *    la palabra es diseño.
 *
 * IntersectionObserver y no un escucha de scroll: ese último corre en cada
 * cuadro, no se agrupa, y traba el desplazamiento justo en los teléfonos
 * modestos que son la mayoría del público.
 */
(function () {
  var barra = document.getElementById('barra-cta');
  if (!barra) return;

  var hero = document.getElementById('top');
  var cierre = document.querySelector('.cierre');

  // Sin IntersectionObserver la barra no aparece nunca, y está bien: la página
  // tiene otros seis botones. Es una mejora, no un requisito.
  if (!('IntersectionObserver' in window) || !hero) return;

  var pasoElHero = false;
  var estaElCierre = false;

  function actualizar() {
    barra.classList.toggle('visible', pasoElHero && !estaElCierre);
  }

  new IntersectionObserver(function (entradas) {
    pasoElHero = !entradas[0].isIntersecting;
    actualizar();
  }, { threshold: 0 }).observe(hero);

  if (cierre) {
    new IntersectionObserver(function (entradas) {
      estaElCierre = entradas[0].isIntersecting;
      actualizar();
    }, { threshold: 0 }).observe(cierre);
  }
})();
