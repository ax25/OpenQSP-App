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
