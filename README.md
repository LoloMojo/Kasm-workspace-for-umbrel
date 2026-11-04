# Kasm Workspaces App Store for umbrelOS

A community app store that packages **Kasm Workspaces** (browser-streamed
desktops and apps) for umbrelOS.

Add this repository in umbrelOS under
`App Store -> Community app stores`:

```
https://github.com/LoloMojo/Kasm-workspace-for-umbrel
```

| Field | Value |
|---|---|
| Store id | `kasm` |
| Apps | `kasm-workspaces` |
| App port | `8443` |

## Apps

### kasm-workspaces — Kasm Workspaces 1.19.0

Kasm Workspaces streams full desktops and single apps (Firefox, Chrome,
VS Code, …) from Docker containers on your server to any browser tab —
no client installation anywhere.

This package reproduces the official Kasm single-server install:

- **Services** — `kasm_db` (PostgreSQL), `kasm_api`, `kasm_manager`,
  `kasm_agent`, `kasm_guac` (streaming gateway) and the Kasm nginx proxy,
  wired exactly as Kasm's `docker-compose-all.yaml`, minus the optional RDP
  gateways.
- **Config** — the vendor-supplied 1.19.0 config templates are copied by a
  one-shot `bootstrap` service, which also generates per-install self-signed
  certs and writes the derived secrets into the config tree. A second
  one-shot (`db-init`) seeds the database with Kasm's default users, settings
  and the workspace image catalog (using the API image's own
  `server.pyc --initialize-database`, the same path the stock `db_init`
  utility takes).
- **Images** — service images are pinned to Kasm's rolling channel
  (`1.19.0-rolling`); workspace images are pulled from Docker Hub on first
  launch of each app (~1–3 GB each).

### Login

| Account | Password |
|---|---|
| `admin@kasm.local` | your Umbrel app password (shown in the app's Settings) |
| `user@kasm.local` | the same Umbrel app password |

### ⚠ Security note

Kasm's architecture requires the `kasm_agent` container to mount the **host
Docker socket** (`/var/run/docker.sock`) so it can spawn per-user session
containers on demand. That is root-equivalent access to the Docker daemon and
is exactly what Kasm's own installer does on a bare server. It is also why
this cannot be submitted to the official Umbrel App Store. Only install this
app on a server you fully control and trust.

Non-official community apps are not reviewed by Umbrel. Install at your own
discretion.
