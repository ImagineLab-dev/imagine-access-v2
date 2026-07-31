import 'dart:typed_data';

/// Archivo elegido por el usuario.
///
/// La clase se define en los DOS lados —acá y en `file_picker_web.dart`— porque
/// un `export` condicional intercambia la biblioteca entera, no partes de ella.
/// Las dos definiciones tienen que mantenerse iguales.
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

/// Fuera del navegador no hay selector de archivos: devuelve null, igual que
/// cuando la persona cancela.
Future<PickedFile?> pickFile({String accept = 'image/*'}) async => null;
