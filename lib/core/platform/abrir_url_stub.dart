/// Sin navegador no hay pestañas. Existe para que las suites que corren en la
/// VM de Dart puedan compilar las pantallas que llaman a esto.
class PestanaReservada {
  const PestanaReservada();
  void navegarA(String url) {}
  void cerrar() {}
}

PestanaReservada reservarPestana() => const PestanaReservada();

void abrirEnPestanaNueva(String url) {}
