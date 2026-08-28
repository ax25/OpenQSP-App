# OpenQSP-App
Multiplatform OpenQSP Client App

## Internet server configuration

The app reads the OpenQSP Internet API location from the bundled `.env` file.
Copy `.env.example` when creating another environment and set
`OPENQSP_SERVER_HOST`, `OPENQSP_SERVER_PORT`, and `OPENQSP_SERVER_SSL`. The
current development configuration uses HTTP on port 8000; Android cleartext
traffic is enabled only in debug builds.

Flutter web makes the status request directly from the browser. The Internet
API must therefore allow the Flutter web application's origin in its server-side
CORS configuration; the app does not bypass browser CORS enforcement.
