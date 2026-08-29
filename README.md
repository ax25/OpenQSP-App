# OpenQSP-App
Multiplatform OpenQSP Client App

## Server configuration

The Internet API is configured through the `.env` asset. Copy `.env.example` to
`.env` for local development, then set `OPENQSP_SERVER_HOST`,
`OPENQSP_SERVER_PORT`, and `OPENQSP_SERVER_SSL`. Do not put passwords or tokens
in a bundled environment file.

Android debug builds allow cleartext HTTP for the current local development
server; release builds retain Android's default network security policy. Flutter
web deployments also require the Internet API server to allow the web app's
origin through its CORS configuration.

## Android Bluetooth TNC roadmap

Settings → APRS supports selecting a previously paired Bluetooth Classic/SPP
TNC, persisting that selection, and opening/closing a test connection. This
uses a small Flutter platform-channel adapter over Android's public Bluetooth
API instead of adding an external Bluetooth package; it keeps the transport
interface isolated and avoids depending on the currently fragmented Classic
Bluetooth plugin ecosystem.

- [x] Bluetooth TNC configuration
- [x] Bluetooth connection test
- [ ] KISS framing
- [ ] AX.25 encode/decode
- [ ] APRS message integration

No KISS, AX.25, or APRS traffic is produced by this layer yet. Device discovery
is deliberately out of scope: pair the TNC in Android settings first.

On Android 12 and newer the app requests `BLUETOOTH_CONNECT` when the user opens
the paired-device picker or tests a connection. On Android 11 and older the
manifest uses the legacy `BLUETOOTH`/`BLUETOOTH_ADMIN` permissions. It does not
request `BLUETOOTH_SCAN` or location because this version never performs device
discovery.

To test with hardware, pair an SPP-capable TNC in Android's Bluetooth settings,
then open OpenQSP → the settings gear → APRS → TNC KISS Bluetooth. Tap
**Seleccionar TNC**, grant the permission, choose the paired address, and tap
**Probar conexión**. A **Conectada** state confirms that the RFCOMM/SPP socket
opened; tap **Desconectar** before leaving the screen, or **Olvidar TNC** to
disconnect and delete the persisted selection. Leaving Settings also closes a
test socket automatically.
