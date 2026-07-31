import 'package:web/web.dart' as web;

/// Host real desde el que se está sirviendo la app.
String zonaHostActual() => web.window.location.hostname.toLowerCase();
