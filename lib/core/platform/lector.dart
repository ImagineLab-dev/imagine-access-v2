// Lector de QR sobre el decodificador nativo del navegador.
//
// La implementación real está en `lector_web.dart`; en la VM de Dart —los
// tests— se usa el stub, que dice "no disponible" y no hace nada.
export 'lector_stub.dart' if (dart.library.js_interop) 'lector_web.dart';
