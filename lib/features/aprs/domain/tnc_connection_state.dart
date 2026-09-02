enum TncConnectionState {
  loading('Loading'),
  notConfigured('Not configured'),
  configured('Configured'),
  connecting('Connecting'),
  connected('Connected'),
  error('Error');

  const TncConnectionState(this.label);
  final String label;
}

enum TncFailure {
  unavailable('Bluetooth is not available'),
  disabled('Bluetooth is disabled'),
  permissionDenied('Bluetooth permission was not granted'),
  deviceNotFound('The configured device is no longer available'),
  timeout('The TNC connection timed out'),
  connectionFailed('Could not connect to the TNC'),
  unknown('A Bluetooth error occurred');

  const TncFailure(this.message);
  final String message;
}
