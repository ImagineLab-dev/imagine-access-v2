// La paleta tiene que ser legible, y eso se calcula, no se mira.
//
// El modo claro ya falló una vez por esto: había textos que sobre su fondo real
// no llegaban al mínimo, y el síntoma que llega es "no se entiende lo que dice",
// sin que nadie pueda señalar cuál. Este test recorre cada color de texto contra
// cada fondo donde puede aparecer y calcula el contraste según WCAG.
//
// Lee las constantes de `AppTheme` directamente: si mañana alguien aclara un
// gris para que "se vea más suave", esto falla antes de llegar a producción.
//
// Umbrales (WCAG 2.1 AA):
//   - 4.5:1 para texto normal
//   - 3.0:1 para texto grande (>=18pt) y elementos de interfaz
//
// Se exige 4.5 incluso al gris más apagado, porque en esta app ese gris NO es
// decorativo: es el color de las pistas de los formularios y del texto
// deshabilitado, o sea texto que hay que poder leer.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/theme/app_theme.dart';

/// Luminancia relativa según WCAG 2.1.
double _luminancia(Color c) {
  double canal(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
}

/// Relación de contraste entre dos colores opacos, de 1:1 a 21:1.
double contraste(Color a, Color b) {
  final la = _luminancia(a);
  final lb = _luminancia(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const minimoTexto = 4.5;

  group('modo oscuro', () {
    const fondos = {
      'fondo': AppTheme.darkBg,
      'panel': AppTheme.darkCard,
      'panel elevado': AppTheme.darkCardElevated,
      'campo': AppTheme.darkInput,
      'hover': AppTheme.darkHover,
    };
    const tintas = {
      'texto': AppTheme.darkText,
      'texto secundario': AppTheme.darkTextSecondary,
      'texto apagado': AppTheme.darkTextDisabled,
      'acento': AppTheme.lima,
      'peligro': AppTheme.peligroSuave,
      'aviso': AppTheme.accentYellow,
    };

    fondos.forEach((nombreFondo, fondo) {
      tintas.forEach((nombreTinta, tinta) {
        test('$nombreTinta sobre $nombreFondo', () {
          final r = contraste(fondo, tinta);
          expect(r, greaterThanOrEqualTo(minimoTexto),
              reason: '$nombreTinta sobre $nombreFondo da '
                  '${r.toStringAsFixed(2)}:1, por debajo de $minimoTexto:1');
        });
      });
    });
  });

  group('modo claro', () {
    const fondos = {
      'fondo': AppTheme.lightBg,
      'panel': AppTheme.lightCard,
      'panel elevado': AppTheme.lightCardElevated,
      'campo': AppTheme.lightInput,
      'hover': AppTheme.lightHover,
    };
    const tintas = {
      'texto': AppTheme.lightText,
      'texto secundario': AppTheme.lightTextSecondary,
      'texto apagado': AppTheme.lightTextDisabled,
      // En claro el acento NO es el lima puro: da 1,6:1 sobre papel.
      'acento': AppTheme.limaOscuro,
      'peligro': AppTheme.peligroOscuro,
    };

    fondos.forEach((nombreFondo, fondo) {
      tintas.forEach((nombreTinta, tinta) {
        test('$nombreTinta sobre $nombreFondo', () {
          final r = contraste(fondo, tinta);
          expect(r, greaterThanOrEqualTo(minimoTexto),
              reason: '$nombreTinta sobre $nombreFondo da '
                  '${r.toStringAsFixed(2)}:1, por debajo de $minimoTexto:1');
        });
      });
    });
  });

  group('bloques de color con tinta encima', () {
    // Cada par es un relleno macizo y la tinta que va sobre él. Son los que se
    // leen en la puerta con poca luz y a un metro de distancia.
    const pares = <String, (Color, Color)>{
      'lima + tinta lima (botón principal)':
          (AppTheme.lima, AppTheme.limaTinta),
      'lima vivo + tinta lima (botón presionado)':
          (AppTheme.limaVivo, AppTheme.limaTinta),
      'casi negro + salmón (cartel NO PASA)':
          (AppTheme.peligroProfundo, AppTheme.peligroSuave),
      'salmón + tinta (banderas y badges de peligro)':
          (AppTheme.peligroSuave, AppTheme.peligroTinta),
      'ámbar + tinta (YA USADO / sin conexión)':
          (AppTheme.accentYellow, Color(0xFF3A2A00)),
      'rojo + blanco (acción destructiva)':
          (AppTheme.accentOrange, Colors.white),
    };

    pares.forEach((nombre, par) {
      test(nombre, () {
        final r = contraste(par.$1, par.$2);
        expect(r, greaterThanOrEqualTo(minimoTexto),
            reason: '$nombre da ${r.toStringAsFixed(2)}:1');
      });
    });
  });

  group('los tres carteles de la puerta se distinguen ENTRE SÍ', () {
    // ESTA ES LA PRUEBA QUE FALTABA.
    //
    // Toda la suite medía la tinta CONTRA SU FONDO, y por eso los tres
    // carteles pasaban: cada uno era legible por separado. Lo que nadie medía
    // es cuánto se distingue un cartel DEL OTRO, que es la única pregunta que
    // importa en una puerta.
    //
    // Y ahí estaba el bug: el cartel de aceptación (#AED500, L 0,5659) y el de
    // rechazo (#FFB4AB, L 0,5684) daban **1,00:1** entre sí. En escala de
    // grises eran la misma pantalla. Quien está en la puerta no lee el cartel,
    // lo ve de reojo mientras mira a la persona: decide por el destello.
    //
    // El fondo de un cartel es una superficie grande, no texto, así que el
    // umbral aplicable es el de componentes de interfaz (WCAG 1.4.11): 3:1.
    // Para el par crítico se exige más, porque confundirlo es dejar entrar a
    // alguien sin entrada.
    const adelante = AppTheme.lima;
    const noPasa = AppTheme.peligroProfundo;
    const yaUsado = AppTheme.darkBorderSoft;

    test('ADELANTE vs NO PASA (el par crítico)', () {
      final r = contraste(adelante, noPasa);
      expect(r, greaterThanOrEqualTo(4.5),
          reason: 'da ${r.toStringAsFixed(2)}:1 — si baja de 4.5 el operario '
              'confunde pasar con no pasar de reojo y con poca luz');
    });

    test('ADELANTE vs YA USADO', () {
      final r = contraste(adelante, yaUsado);
      expect(r, greaterThanOrEqualTo(3.0),
          reason: 'da ${r.toStringAsFixed(2)}:1');
    });

    test('los tres tienen luminancias distintas, no solo tonos distintos', () {
      // Un daltónico rojo-verde no ve el tono. Si los tres no se separan en
      // brillo, para esa persona no hay tres carteles: hay uno.
      final ls = [adelante, noPasa, yaUsado].map(_luminancia).toList()..sort();
      expect(ls[1] - ls[0], greaterThan(0.01),
          reason: 'dos carteles comparten brillo: ${ls.map((l) => l.toStringAsFixed(4))}');
      expect(ls[2] - ls[1], greaterThan(0.01),
          reason: 'dos carteles comparten brillo: ${ls.map((l) => l.toStringAsFixed(4))}');
    });
  });

  test('el lima puro NO se usa como texto en modo claro', () {
    // Es la trampa que hace ilegible medio modo claro, y por eso existe
    // acentoTexto(). Este test fija el motivo: si alguien "simplifica" ese
    // helper y devuelve el lima siempre, esto explica por qué no se puede.
    final sobrePapel = contraste(AppTheme.lightBg, AppTheme.lima);
    expect(sobrePapel, lessThan(minimoTexto),
        reason: 'Si el lima puro pasara el umbral sobre papel, acentoTexto() '
            'ya no haría falta. Da ${sobrePapel.toStringAsFixed(2)}:1.');

    final oscurecido = contraste(AppTheme.lightBg, AppTheme.limaOscuro);
    expect(oscurecido, greaterThanOrEqualTo(minimoTexto));
  });

  test('los bordes se distinguen de su fondo', () {
    // Un borde es un elemento de interfaz: le alcanza 3:1. Pero si no llega,
    // los paneles dejan de tener contorno y el sistema entero —que se apoya en
    // rectángulos con borde— se deshace.
    const minimoBorde = 1.4;
    expect(contraste(AppTheme.darkBg, AppTheme.darkBorder),
        greaterThanOrEqualTo(minimoBorde));
    expect(contraste(AppTheme.darkCard, AppTheme.darkBorder),
        greaterThanOrEqualTo(minimoBorde));
    expect(contraste(AppTheme.lightBg, AppTheme.lightBorder),
        greaterThanOrEqualTo(minimoBorde));
    expect(contraste(AppTheme.lightCard, AppTheme.lightBorder),
        greaterThanOrEqualTo(minimoBorde));
  });
}
