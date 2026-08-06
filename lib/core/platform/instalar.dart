// Instalación de la PWA desde dentro de la app.
//
// La implementación real está en `instalar_web.dart`; fuera del navegador
// —los tests— se usa el stub, que dice "ya instalada" para que nada la ofrezca.
export 'instalar_stub.dart' if (dart.library.js_interop) 'instalar_web.dart';
