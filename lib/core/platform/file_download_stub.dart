import 'dart:typed_data';

/// Descarga de archivos fuera del navegador: no hay dónde descargar.
///
/// Existe para que el árbol que llega hasta acá —`event_report_service`,
/// `admin_dashboard_view`, `dashboard_screen`, `app_router`— se pueda importar
/// en la VM de Dart. Antes `file_download.dart` importaba `dart:js_interop`
/// directo y eso volvía intesteable a todo eso, sin que nada lo señalara: los
/// tests pasaban porque ninguno lo tocaba.
///
/// No lanza: una descarga que no ocurre en un test no es un error, y lanzar
/// obligaría a envolver cada llamada en un try solo por el entorno de prueba.
void downloadBytes(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) {}
