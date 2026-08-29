enum TncConnectionState {
  loading('Cargando'),
  notConfigured('No configurada'),
  configured('Configurada'),
  connecting('Conectando'),
  connected('Conectada'),
  error('Error');

  const TncConnectionState(this.label);
  final String label;
}

enum TncFailure {
  unavailable('Bluetooth no está disponible'),
  disabled('Bluetooth está desactivado'),
  permissionDenied('Permiso Bluetooth no concedido'),
  deviceNotFound('El dispositivo configurado ya no está disponible'),
  timeout('La conexión con la TNC agotó el tiempo de espera'),
  connectionFailed('No se pudo conectar con la TNC'),
  unknown('Se produjo un error Bluetooth');

  const TncFailure(this.message);
  final String message;
}
