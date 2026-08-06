// Fuera del navegador no hay `BarcodeDetector` ni elemento de video.
//
// Devuelve "no disponible" en vez de lanzar: quien llama tiene que poder
// preguntar sin envolver todo en un try, y el camino de ZXing sigue siendo
// válido cuando esto dice que no.

bool get lectorNativoDisponible => false;

/// Devuelve 0: no hay sesión porque no hay lector.
int iniciarLectorNativo(void Function(String codigo) alEncontrar) => 0;

void detenerLectorNativo(int sesion) {}

String estadoDelLector() => '{}';
