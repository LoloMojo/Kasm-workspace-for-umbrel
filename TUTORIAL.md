# Kasm Workspaces on umbrelOS — first-run guide

## Install

1. Add the store: **App Store → Community app stores → Add** with
   `https://github.com/LoloMojo/Kasm-workspace-for-umbrel`.
2. Open **Kasm Workspaces** and press **Install**. This pulls the six Kasm
   service images (about 2 GB) and boots the stack: bootstrap → database →
   DB seed → API / manager / agent / guac / proxy. First start may take a few
   minutes.

## Login

| Role | Username | Password |
|---|---|---|
| Admin | `admin@kasm.local` | your **Umbrel app password** (Settings → App Password) |
| User | `user@kasm.local` | same Umbrel app password |

Both accounts are created during the DB seed with the same password. Change
them from the Kasm Admin menu (`http(s)://<umbrel>:8443` → login as admin →
Users).

## First launch of a workspace

- Open the app from the Umbrel home screen (or browse to
  `https://<umbrel-address>:8443`). Your browser shows a certificate warning —
  this is Umbrel's local HTTPS proxy; click through.
- The first launch of each workspace (Firefox, Chrome, Desktop, …) downloads
  its Docker image on the spot (1–3 GB) — subsequent launches are instant.
- Sessions idle-logout after 20 minutes by default (Admin → Settings →
  Session logging / Kasm policy).

## Operational notes

- **Data lives in** `/home/umbrel/umbrel/app-data/kasm-workspaces/data`:
  the whole Kasm config tree (`kasm/`) and the PostgreSQL volume (`db/`).
  Back these up; a wipe resets Kasm to first install.
- **Updates**: this app pins Kasm's *rolling* image channel; restarting the
  app (App Settings → Restart) picks up newer rolling images on the next
  container recreate.
- **Workspace catalog**: the DB seed registers 53 workspace images, 24 ships
  enabled (browser, desktop, terminal, office, dev tools). Enable more from
  Admin → Images, or add any `kasmweb/*` image by name; first launch of each
  downloads its image from Docker Hub.
- **Docker socket**: the `kasm_agent` service mounts `/var/run/docker.sock`
  to create session containers — see the Security note in this store's
  README. Facts: only Kasm's own images get pulled; sessions are removed on
  stop/expiry. Do not install this app on a machine you don't fully trust.

## Troubleshooting

- **App stuck at "starting" / proxy 502 for several minutes** — the DB seed
  runs alembic migrations + seed inserts; give it 2–5 minutes on first boot.
  Check the app status again after a while.
- **「Service Unavailable」 after restart** — the one-shot `db-init` and
  `bootstrap` services are marked with a completion flag in
  `data/kasm/conf/`; if a flag is missing after a crash, remove the partial
  state via SSH (`umbrel` → `sudo rm -rf
  /home/umbrel/umbrel/app-data/kasm-workspaces/data/kasm/.db-*`) and restart.
- **Session won't start / image pull error** — verify the workspace image
  name is right and the agent can pull it (`kasm_agent` logs show pulls):
  check the Umbrel app logs for the agent container, or pull the image
  manually on the host with `docker pull kasmweb/firefox:1.19.0-rolling-daily`
  and retry.
- **Camera/microphone** — requires a secure context: open the app via
  `https://` (Umbrel's proxy), then grant site permission in the browser.
