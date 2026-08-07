import 'package:flutter/material.dart';

/// Identidad visual: **terminal de control de acceso**.
///
/// La app se veía como cualquier plantilla generada por IA —Inter, glass,
/// gradiente azul/violeta, todo redondeado—. Esta identidad la ata a lo que el
/// producto realmente es: el panel de una puerta. Las decisiones de marca:
///
///   - **Un solo acento: lima `#AED500`.** Nada de azul ni violeta. El lima es
///     "energía / validado / adelante", y al ser uno solo, cuando aparece
///     significa algo. Sobre él, tinta lima oscura `#293500`, nunca blanco.
///   - **Ángulo recto en todo.** `radiusCard` y `radiusField` son 0. Las
///     esquinas redondeadas son la firma más delatora de la plantilla; una
///     credencial, un formulario técnico y un panel de control son cuadrados.
///   - **Tres fuentes con oficio distinto.** Grotesca en caja alta para
///     titulares y etiquetas, Chivo para texto corrido, mono para todo dato
///     que tenga que alinear en columna (seriales, montos, horas, contadores).
///   - **Semántica del control de acceso con color plano, no con glow:** lima
///     = validado, salmón/rojo = denegado, ámbar = ya usado.
///
/// Los NOMBRES de los tokens se mantienen a propósito (los referencian decenas
/// de pantallas); acá solo cambian los valores. Cambiar la marca es reescribir
/// este archivo, no cien.
///
/// El modo claro **no** es el oscuro invertido: el lima sobre papel tiene
/// contraste ~1.6:1 y es ilegible como texto. Por eso existe [acentoTexto],
/// que en claro devuelve el lima oscurecido. Como *relleno* de botón el lima
/// va igual en los dos modos, porque encima lleva tinta oscura.
class AppTheme {
  // ---------------------------------------------------------------- FUENTES

  /// Titulares, etiquetas, botones y navegación. Siempre en MAYÚSCULAS: es la
  /// voz de la marca.
  static const String fontDisplay = 'SpaceGrotesk';

  /// Texto corrido, descripciones, párrafos. Legible en caja baja, cosa que la
  /// grotesca en caja alta no es.
  static const String fontBody = 'Chivo';

  /// Seriales, códigos, montos, horas, contadores: todo "dato de ticket".
  /// Monoespaciada para que alinee en columna y para que un código se pueda
  /// leer carácter por carácter sin ambigüedad.
  static const String fontMono = 'JetBrainsMono';

  // ------------------------------------------------------------------ ACENTO

  /// El lima de la marca. Único acento del sistema.
  static const Color lima = Color(0xFFAED500);

  /// Lima encendido: hover y estados de énfasis.
  static const Color limaVivo = Color(0xFFC7F300);

  /// Tinta que va ENCIMA del lima. Nunca blanco: sobre lima el blanco tiene
  /// contraste 1.9:1 y es ilegible.
  static const Color limaTinta = Color(0xFF293500);

  /// Lima oscurecido para usar como TEXTO sobre fondo claro (contraste ~7:1).
  static const Color limaOscuro = Color(0xFF4F6200);

  // ------------------------------------------------------- MODO OSCURO (base)

  static const Color darkBg = Color(0xFF0A0A0B); // el fondo de la app
  static const Color darkCard = Color(0xFF131315); // panel
  static const Color darkCardElevated = Color(0xFF1F1F21); // panel elevado
  static const Color darkInput = Color(0xFF1B1B1D); // campo de formulario
  static const Color darkHover = Color(0xFF2A2A2C); // relleno de hover
  static const Color darkBorder = Color(0xFF46464A);
  static const Color darkBorderSoft = Color(0xFF353437);
  static const Color darkText = Color(0xFFE4E2E4);
  static const Color darkTextSecondary = Color(0xFFC7C6CA);
  static const Color darkTextDisabled = Color(0xFF919094);

  // -------------------------------------------------------- MODO CLARO (papel)

  static const Color lightBg = Color(0xFFF4F4F1);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardElevated = Color(0xFFFAFAF8);
  static const Color lightInput = Color(0xFFEDEDEA);
  static const Color lightHover = Color(0xFFE6E6E1);
  /// Se oscureció desde `#D2D2CE`, que contra el fondo de página daba 1,38:1
  /// —prácticamente invisible—. Todo este sistema son rectángulos con un borde
  /// de un píxel: un borde que no se ve deja los paneles disueltos sobre el
  /// fondo y la pantalla entera se lee lavada. Este valor iguala la presencia
  /// que tiene el borde del modo oscuro (1,9:1 sobre su panel).
  static const Color lightBorder = Color(0xFFBDBDB7);
  /// Separador interno: notablemente más tenue que [lightBorder], pero visible.
  static const Color lightBorderSoft = Color(0xFFD8D8D2);
  static const Color lightText = Color(0xFF131315);
  static const Color lightTextSecondary = Color(0xFF5B5B5F);
  /// 5,0:1 en su peor fondo (el relleno de hover).
  ///
  /// Estaba en `#8A8A8E` y ahí daba 2,93:1: por debajo del mínimo incluso para
  /// texto grande. Como es el color de las pistas de los formularios y del
  /// texto deshabilitado, era literalmente "no se entiende lo que dice" en modo
  /// claro. No es un gris elegido a ojo: es el más claro que pasa el umbral
  /// contra los cuatro fondos donde puede aparecer.
  static const Color lightTextDisabled = Color(0xFF606064);

  // ---------------------------------------------------------------- SEMÁNTICA

  /// Validado / adelante. Es el mismo lima: en esta app "verde" ES el lima.
  static const Color accentGreen = lima;

  /// Ya usado / atención. Ámbar.
  static const Color accentYellow = Color(0xFFFFC107);

  /// Denegado / destructivo. Rojo que funciona como relleno en los dos modos.
  ///
  /// Se oscureció desde `#E5484D`, que con texto blanco encima daba 3,91:1 —el
  /// botón de suspender una organización, justo el que conviene leer bien—.
  static const Color accentOrange = Color(0xFFCC3339);

  /// Salmón claro. Era el fondo del cartel DENEGADO y ahora es su TINTA:
  /// ver [peligroProfundo].
  static const Color peligroSuave = Color(0xFFFFB4AB);

  /// Tinta que va encima de [peligroSuave] cuando el salmón hace de fondo
  /// (banderas, badges). En el cartel de la puerta ya no se usa así.
  static const Color peligroTinta = Color(0xFF690005);

  /// Fondo del cartel NO PASA a pantalla completa.
  ///
  /// POR QUÉ ES CASI NEGRO Y NO EL SALMÓN
  ///
  /// El cartel de rechazo era [peligroSuave] `#FFB4AB` y el de aceptación es
  /// [lima] `#AED500`. Se ven distintos, pero sus luminancias relativas son
  /// 0,5684 y 0,5659: **el contraste ENTRE los dos carteles era 1,00:1**. En
  /// escala de grises son la misma pantalla.
  ///
  /// Eso importa porque quien está en la puerta no lee el cartel: lo ve de
  /// reojo, de noche, mientras mira a la persona. Decide por el destello. Y
  /// los cuatro refuerzos que deberían salvarlo fallaban los cuatro: los dos
  /// íconos eran círculos macizos del mismo tamaño, los dos titulares
  /// empezaban con la palabra "ACCESO", la háptica no se mapea en web, y el
  /// proyecto no tiene ni una dependencia de audio.
  ///
  /// Con este valor el par crítico pasa de 1,00:1 a **10,43:1**, y la
  /// diferencia sobrevive al daltonismo rojo-verde, a la poca luz y a la
  /// visión periférica, porque es de BRILLO y no de tono.
  ///
  /// El salmón no se tira: pasa a ser la tinta encima, con 10,47:1.
  static const Color peligroProfundo = Color(0xFF3A0002);

  /// Rojo legible como TEXTO sobre fondo claro.
  static const Color peligroOscuro = Color(0xFFB3261E);

  /// Secundario categórico: acero frío. Existe para que un gráfico o un panel
  /// con dos métricas pueda distinguirlas sin meter un color nuevo a la marca
  /// —y para que el lima siga siendo el único que grita—.
  static const Color accentPurple = Color(0xFF8A8F98);

  // Alias históricos. Todos apuntan al acento único: el sistema tiene UNO.
  static const Color primaryColor = lima;
  static const Color accentBlue = lima;
  static const Color accentCyan = lima;
  static const Color neonBlue = lima;
  static const Color neonGreen = lima;
  static const Color neonPurple = accentPurple;
  static const Color neonOrange = accentYellow;

  static const Color errorColor = accentOrange;
  static const Color successColor = lima;
  static const Color warningColor = accentYellow;

  // Alias de superficie usados por pantallas antiguas.
  static const Color scaffoldBackgroundColor = darkBg;
  static const Color surfaceColor = darkCard;
  static const Color lightScaffoldBackgroundColor = lightBg;
  static const Color lightSurfaceColor = lightCard;

  // ------------------------------------------------------------------ FORMA

  /// Ángulo recto. No es un descuido: es la decisión de marca más visible.
  static const double radiusCard = 0;
  static const double radiusField = 0;

  /// Grosor del borde de panel. Un pelo, como un plano técnico.
  static const double bordeAncho = 1;

  /// Paso de la retícula de fondo, en píxeles.
  static const double gridPaso = 32;

  // --------------------------------------------------- AYUDAS DEPENDIENTES DE MODO
  //
  // Un color que sirve en oscuro puede ser ilegible en claro. Estos helpers
  // evitan que cada pantalla tenga que acordarse de eso.

  static bool esOscuro(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// El acento **como texto**. En claro devuelve el lima oscurecido, porque el
  /// lima puro sobre papel no se lee.
  static Color acentoTexto(BuildContext context) =>
      esOscuro(context) ? lima : limaOscuro;

  /// El acento **como relleno** (botón, barra, chip). Igual en los dos modos:
  /// encima siempre va [limaTinta].
  static Color acentoRelleno(BuildContext context) => lima;

  /// Rojo legible como texto en el modo actual.
  static Color peligroTexto(BuildContext context) =>
      esOscuro(context) ? peligroSuave : peligroOscuro;

  static Color fondo(BuildContext context) => esOscuro(context) ? darkBg : lightBg;
  static Color panel(BuildContext context) => esOscuro(context) ? darkCard : lightCard;
  static Color panelElevado(BuildContext context) =>
      esOscuro(context) ? darkCardElevated : lightCardElevated;
  static Color campo(BuildContext context) => esOscuro(context) ? darkInput : lightInput;
  static Color hover(BuildContext context) => esOscuro(context) ? darkHover : lightHover;
  static Color borde(BuildContext context) => esOscuro(context) ? darkBorder : lightBorder;
  static Color bordeSuave(BuildContext context) =>
      esOscuro(context) ? darkBorderSoft : lightBorderSoft;
  static Color texto(BuildContext context) => esOscuro(context) ? darkText : lightText;
  static Color textoSecundario(BuildContext context) =>
      esOscuro(context) ? darkTextSecondary : lightTextSecondary;
  static Color textoApagado(BuildContext context) =>
      esOscuro(context) ? darkTextDisabled : lightTextDisabled;

  // ------------------------------------------------------- ESTILOS CON NOMBRE
  //
  // Tres gestos tipográficos que se repiten en toda la app. Tenerlos acá evita
  // que cada pantalla invente su propia variante y que el conjunto se
  // desalinee.

  /// Etiqueta de sección o de campo: grotesca, MAYÚSCULAS, tracking abierto.
  static TextStyle etiqueta(
    BuildContext context, {
    double size = 11,
    Color? color,
    FontWeight peso = FontWeight.w700,
  }) =>
      TextStyle(
        fontFamily: fontDisplay,
        fontSize: size,
        fontWeight: peso,
        letterSpacing: 1.1,
        height: 1.2,
        color: color ?? textoSecundario(context),
      );

  /// Dato: mono, para códigos, montos, horas y contadores.
  static TextStyle dato(
    BuildContext context, {
    double size = 12,
    Color? color,
    FontWeight peso = FontWeight.w700,
    double? tracking,
  }) =>
      TextStyle(
        fontFamily: fontMono,
        fontSize: size,
        fontWeight: peso,
        letterSpacing: tracking,
        height: 1.3,
        color: color ?? texto(context),
      );

  /// Titular: grotesca, MAYÚSCULAS, tracking cerrado y peso alto.
  static TextStyle titular(
    BuildContext context, {
    double size = 22,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: fontDisplay,
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.05,
        color: color ?? texto(context),
      );

  // ----------------------------------------------------------------- THEMES

  static ThemeData darkTheme() => _construir(
        brightness: Brightness.dark,
        bg: darkBg,
        card: darkCard,
        elevado: darkCardElevated,
        input: darkInput,
        hoverColor: darkHover,
        border: darkBorder,
        bordeSuaveColor: darkBorderSoft,
        text: darkText,
        text2: darkTextSecondary,
        text3: darkTextDisabled,
        acentoComoTexto: lima,
        peligro: peligroSuave,
      );

  static ThemeData lightTheme() => _construir(
        brightness: Brightness.light,
        bg: lightBg,
        card: lightCard,
        elevado: lightCardElevated,
        input: lightInput,
        hoverColor: lightHover,
        border: lightBorder,
        bordeSuaveColor: lightBorderSoft,
        text: lightText,
        text2: lightTextSecondary,
        text3: lightTextDisabled,
        acentoComoTexto: limaOscuro,
        peligro: peligroOscuro,
      );

  /// Un solo constructor para los dos modos. Antes estaban duplicados y por eso
  /// divergían —el claro tenía blancos que el oscuro no, y de ahí los textos
  /// que no se leían—. Un origen, dos paletas.
  static ThemeData _construir({
    required Brightness brightness,
    required Color bg,
    required Color card,
    required Color elevado,
    required Color input,
    required Color hoverColor,
    required Color border,
    required Color bordeSuaveColor,
    required Color text,
    required Color text2,
    required Color text3,
    required Color acentoComoTexto,
    required Color peligro,
  }) {
    final formaRecta = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusCard),
    );

    OutlineInputBorder borde({required Color color, double ancho = bordeAncho}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide(color: color, width: ancho),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      fontFamily: fontBody,

      colorScheme: ColorScheme(
        brightness: brightness,
        primary: lima,
        onPrimary: limaTinta,
        primaryContainer: lima,
        onPrimaryContainer: limaTinta,
        secondary: accentPurple,
        onSecondary: brightness == Brightness.dark ? darkBg : Colors.white,
        surface: card,
        onSurface: text,
        surfaceContainerHighest: elevado,
        surfaceContainerHigh: elevado,
        surfaceContainer: card,
        surfaceContainerLow: card,
        surfaceContainerLowest: bg,
        onSurfaceVariant: text2,
        outline: border,
        outlineVariant: bordeSuaveColor,
        error: accentOrange,
        onError: Colors.white,
        errorContainer: peligroSuave,
        onErrorContainer: peligroTinta,
        inverseSurface: text,
        onInverseSurface: bg,
        shadow: Colors.black,
        scrim: Colors.black,
      ),

      // Tipografía: grotesca para lo que titula y etiqueta, Chivo para lo que
      // se lee corrido, mono para lo que se lee dato por dato.
      textTheme: TextTheme(
        displayLarge: TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
            height: 1.0,
            color: text),
        displayMedium: TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.9,
            height: 1.02,
            color: text),
        displaySmall: TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.05,
            color: text),
        headlineLarge: TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.08,
            color: text),
        headlineMedium: TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            height: 1.1,
            color: text),
        headlineSmall: TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            height: 1.15,
            color: text),
        titleLarge: TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: text),
        titleMedium: TextStyle(
            fontFamily: fontDisplay, fontWeight: FontWeight.w700, color: text),
        titleSmall: TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: text2),
        bodyLarge: TextStyle(fontFamily: fontBody, height: 1.5, color: text),
        bodyMedium: TextStyle(fontFamily: fontBody, height: 1.5, color: text2),
        bodySmall: TextStyle(fontFamily: fontBody, height: 1.45, color: text2),
        labelLarge: TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: text),
        labelMedium: TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: text2),
        labelSmall: TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: text3),
      ),

      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: border, width: bordeAncho),
        ),
      ),

      // Campo: caja recta, relleno propio, y foco marcado con el acento —no con
      // un glow, con una línea más gruesa—.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: borde(color: border),
        enabledBorder: borde(color: border),
        focusedBorder: borde(color: lima, ancho: 2),
        errorBorder: borde(color: accentOrange),
        focusedErrorBorder: borde(color: accentOrange, ancho: 2),
        disabledBorder: borde(color: bordeSuaveColor),
        hintStyle: TextStyle(fontFamily: fontMono, fontSize: 13, color: text3),
        labelStyle: TextStyle(
            fontFamily: fontDisplay,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: text2),
        floatingLabelStyle: TextStyle(
            fontFamily: fontDisplay,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: acentoComoTexto),
        helperStyle: TextStyle(fontFamily: fontBody, fontSize: 11, color: text3),
        errorStyle: TextStyle(fontFamily: fontBody, fontSize: 11, color: peligro),
        prefixIconColor: text3,
        suffixIconColor: text3,
      ),

      // Acción principal: bloque lima, recto, en mayúsculas.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lima,
          foregroundColor: limaTinta,
          disabledBackgroundColor: border,
          disabledForegroundColor: text3,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: formaRecta,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 1.2,
          ),
        ),
      ),

      // Acción secundaria: el mismo bloque pero vacío, solo contorno.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: text, width: bordeAncho),
          shape: formaRecta,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 1.2,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: acentoComoTexto,
          shape: formaRecta,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.0,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: lima,
          foregroundColor: limaTinta,
          disabledBackgroundColor: border,
          disabledForegroundColor: text3,
          elevation: 0,
          shape: formaRecta,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 1.2,
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text2,
          shape: formaRecta,
          highlightColor: hoverColor,
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        titleTextStyle: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: text,
        ),
        iconTheme: IconThemeData(color: text2, size: 22),
        actionsIconTheme: IconThemeData(color: text2, size: 22),
        shape: Border(bottom: BorderSide(color: border, width: bordeAncho)),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: acentoComoTexto,
        unselectedItemColor: text2,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0),
        unselectedLabelStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        indicatorShape: formaRecta,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((estados) => TextStyle(
              fontFamily: fontDisplay,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: estados.contains(WidgetState.selected) ? acentoComoTexto : text2,
            )),
        iconTheme: WidgetStateProperty.resolveWith((estados) => IconThemeData(
              size: 22,
              color: estados.contains(WidgetState.selected) ? acentoComoTexto : text2,
            )),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: elevado,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: lima, width: bordeAncho),
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: text,
        ),
        contentTextStyle: TextStyle(fontFamily: fontBody, height: 1.5, color: text2),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: elevado,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: border, width: bordeAncho),
        ),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevado,
        contentTextStyle: TextStyle(fontFamily: fontBody, color: text),
        actionTextColor: lima,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: border, width: bordeAncho),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: input,
        selectedColor: lima,
        disabledColor: bordeSuaveColor,
        side: BorderSide(color: border, width: bordeAncho),
        shape: formaRecta,
        labelStyle: TextStyle(
            fontFamily: fontMono, fontSize: 11, fontWeight: FontWeight.w700, color: text),
        secondaryLabelStyle: const TextStyle(
            fontFamily: fontMono,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: limaTinta),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: acentoComoTexto,
        unselectedLabelColor: text2,
        indicatorColor: lima,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: border,
        labelStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0),
        unselectedLabelStyle: const TextStyle(
            fontFamily: fontDisplay,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((estados) =>
            estados.contains(WidgetState.selected) ? limaTinta : text2),
        trackColor: WidgetStateProperty.resolveWith(
            (estados) => estados.contains(WidgetState.selected) ? lima : input),
        trackOutlineColor: WidgetStateProperty.all(border),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((estados) =>
            estados.contains(WidgetState.selected) ? lima : Colors.transparent),
        checkColor: WidgetStateProperty.all(limaTinta),
        side: BorderSide(color: border, width: 1.4),
        shape: const RoundedRectangleBorder(),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((estados) =>
            estados.contains(WidgetState.selected) ? lima : border),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: lima,
        inactiveTrackColor: input,
        thumbColor: lima,
        overlayColor: lima.withValues(alpha: 0.15),
        trackHeight: 3,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: lima,
        linearTrackColor: input,
        circularTrackColor: input,
        linearMinHeight: 4,
      ),

      dividerTheme: DividerThemeData(color: border, thickness: bordeAncho, space: 1),
      dividerColor: border,

      listTileTheme: ListTileThemeData(
        iconColor: text2,
        textColor: text,
        shape: formaRecta,
        titleTextStyle: TextStyle(fontFamily: fontBody, fontSize: 14, color: text),
        subtitleTextStyle: TextStyle(fontFamily: fontBody, fontSize: 12, color: text2),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: elevado,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: border, width: bordeAncho),
        ),
        textStyle: TextStyle(fontFamily: fontBody, fontSize: 13, color: text),
      ),

      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(elevado),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          elevation: WidgetStateProperty.all(0),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusCard),
            side: BorderSide(color: border, width: bordeAncho),
          )),
        ),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(elevado),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          elevation: WidgetStateProperty.all(0),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusCard),
            side: BorderSide(color: border, width: bordeAncho),
          )),
        ),
        textStyle: TextStyle(fontFamily: fontMono, fontSize: 13, color: text),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: elevado,
          border: Border.all(color: border, width: bordeAncho),
        ),
        textStyle: TextStyle(fontFamily: fontMono, fontSize: 11, color: text),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: lima,
        foregroundColor: limaTinta,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(),
      ),

      iconTheme: IconThemeData(color: text2, size: 22),

      // Sin onda expansiva: en un panel técnico el feedback es un bloque de
      // color que cambia al instante, no una animación de agua.
      splashFactory: NoSplash.splashFactory,
      highlightColor: hoverColor,
      splashColor: Colors.transparent,
      hoverColor: hoverColor,
    );
  }
}
