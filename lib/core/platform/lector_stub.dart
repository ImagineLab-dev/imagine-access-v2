/// Fuera del navegador no hay `BarcodeDetector` ni elemento de video.
///
/// Devuelve "no disponible" en vez de lanzar: quien llama tiene que poder
/// preguntar sin envolver todo en un try, y el camino de ZXing sigue siendo
/// válido cuando esto dice que no.
bool get lectorNativoDisponible => false;

bool iniciarLectorNativo(void Function(String codigo) alEncontrar) => false;

void detenerLectorNativo() {}

String estadoDelLector() => '{}';
