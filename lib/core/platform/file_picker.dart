import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Archivo elegido por el usuario.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;

  /// Extensión sin punto, en minúsculas. Vacía si el archivo no tenía.
  String get extension {
    final punto = name.lastIndexOf('.');
    if (punto < 0 || punto == name.length - 1) return '';
    return name.substring(punto + 1).toLowerCase();
  }
}

/// Abre el selector de archivos del navegador y devuelve el elegido.
///
/// Se implementa con un `<input type="file">` propio en lugar de sumar un
/// paquete: el proyecto es solo web y ya depende de `package:web`, así que la
/// dependencia extra no compraría nada.
///
/// Devuelve `null` si el usuario cancela. Ojo: los navegadores **no** avisan
/// de la cancelación de forma fiable —el evento `cancel` es reciente y no
/// universal— así que quien llame no debe quedarse esperando indefinidamente
/// una respuesta; el future se completa recién cuando hay archivo o cuando el
/// input reporta cancelación.
Future<PickedFile?> pickFile({
  String accept = 'image/*',
}) async {
  final completer = Completer<PickedFile?>();

  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = accept
    ..multiple = false
    ..style.display = 'none';

  void finalizar(PickedFile? resultado) {
    if (!completer.isCompleted) completer.complete(resultado);
    input.remove();
  }

  input.onchange = ((web.Event _) {
    final archivos = input.files;
    if (archivos == null || archivos.length == 0) {
      finalizar(null);
      return;
    }

    final archivo = archivos.item(0);
    if (archivo == null) {
      finalizar(null);
      return;
    }

    // `arrayBuffer()` en vez de FileReader: devuelve una promesa y evita el
    // baile de listeners onload/onerror del API viejo.
    archivo.arrayBuffer().toDart.then((buffer) {
      finalizar(PickedFile(
        name: archivo.name,
        bytes: buffer.toDart.asUint8List(),
        mimeType: archivo.type,
      ));
    }).catchError((Object _) {
      finalizar(null);
      return null;
    });
  }).toJS;

  // Algunos navegadores modernos avisan la cancelación; donde no exista, el
  // future simplemente no se completa y la UI queda como estaba.
  input.oncancel = ((web.Event _) => finalizar(null)).toJS;

  // Tiene que estar en el DOM para que el click funcione en todos los
  // navegadores; se quita en cuanto termina.
  web.document.body!.appendChild(input);
  input.click();

  return completer.future;
}
