enum ResultadoActualizacion { nueva, alDia, sinSoporte }

Future<ResultadoActualizacion> buscarActualizacion() async =>
    ResultadoActualizacion.sinSoporte;
