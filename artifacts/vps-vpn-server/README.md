# VPS VPN Server

Sanitized public artifact of a personal VPS VPN deployment. The repository intentionally contains no domain name, public IP, client link, QR code, UUID, access logs, or active credentials.

## What this demonstrates

- Docker Compose lifecycle for `Xray`;
- `VLESS + WebSocket` transport;
- TLS termination and WebSocket reverse proxy through `Nginx`;
- binding the application port to `127.0.0.1` so the public entry point is only `443/tcp`;
- separation of an existing HTTPS site from a dedicated WebSocket route;
- practical troubleshooting of Nginx configuration activation and end-to-end client connectivity.

## Architecture

```text
Client
  -> HTTPS :443 /vpn-ws
  -> Nginx (TLS termination and WebSocket upgrade)
  -> 127.0.0.1:10000
  -> Xray container
```

## Files

- `docker-compose.yml` starts the Xray container and exposes its port only locally.
- `xray.config.example.json` is a template. Generate a new UUID and keep the real client list outside git.
- `nginx-vpn-ws-location.conf` is included into the TLS-enabled Nginx virtual host.

## Deployment outline

1. Prepare a Linux VPS, Docker Engine, Docker Compose plugin, Nginx, DNS and a valid TLS certificate.
2. Copy the compose file and create a private Xray config from the example with a newly generated UUID.
3. Run `docker compose up -d` and confirm that the service listens only on `127.0.0.1:10000`.
4. Add the Nginx location to the server block on `443`, then run `nginx -t` and reload Nginx.
5. Import a separately generated client profile and test the WebSocket path end-to-end.

## Operational checks

```bash
docker compose ps
docker compose logs --tail=50 xray
ss -lntp | rg ':10000'
nginx -t
curl -Ik https://your-domain.example/
curl -skI --http1.1 https://your-domain.example/vpn-ws
```

An HTTP `400` for the second request without WebSocket upgrade headers can be expected: it demonstrates that Nginx reached Xray rather than serving the website response.

## Security boundary

This is a portfolio template, not an active access endpoint. Do not commit real client profiles, TLS private keys, domains, IPs, logs, credentials, or QR codes.
