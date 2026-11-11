# Kasm Workspaces on umbrelOS — Agent Handoff Guide

You are the Hermes agent on the umbrelOS PC where **Kasm Workspaces** (app id
`kasm-workspaces`, store `kasm`, Kasm 1.19.0 rolling) has been installed.
The install reportedly **stuck at 99%**. This file gives you everything you
need to diagnose, finish, and verify the install. It was written by the agent
that built and config-verified the app package on another PC.

## 0. Where the package lives

- Public store repo: `https://github.com/LoloMojo/Kasm-workspace-for-umbrel`
  (store id `kasm`, app folder `kasm-workspaces/`)
- Installed app data:
  `/home/umbrel/umbrel/app-data/kasm-workspaces/`
  - `data/kasm/` = generated config tree + TLS certs (created by `bootstrap`)
  - `data/db/` = PostgreSQL data volume
- Store URL to (re)add in umbrelOS: `https://github.com/LoloMojo/Kasm-workspace-for-umbrel`

Use the `umbrel` MCP tools for anything on umbrelOS itself
(`mcp__umbrel__list_apps`, `mcp__umbrel__get_app_status`,
`mcp__umbrel__get_notifications`). If they are not connected, ask the user to
enable them (Settings → AI agents → Hermes Agent) and grant app access.

## 1. Architecture (9 compose services — know the chain)

```
bootstrap  (one-shot: generates config tree, certs, secrets; idempotent via marker)
    └─> db   (kasmweb/postgres:1.19.0-rolling)
            └─> db-init  (one-shot: alembic schema + seeds users/settings/images/agents)
                    └─> kasm_api, kasm_manager
                            └─> kasm_agent, kasm_guac, proxy
                                    └─> app_proxy (env-only; umbrelOS 2.0 gateway)
```

- All service images are `kasmweb/*:1.19.0-rolling` (public Docker Hub,
  amd64 + arm64) — about 1.2 GB total on the disk.
- **Workspace images (Firefox, Chrome, Desktop, …) are NOT downloaded at
  install.** They are catalog rows only (53 seeded, 24 enabled) and each one
  is pulled from Docker Hub on its **first launch** (1–3 GB each). This is
  intentional: "only what you use" — do not "fix" it by bulk-pulling.
- Browser access: umbrelOS gateway serves `https://<umbrel>:8443`, terminates
  TLS with umbrel's cert, and forwards **plain HTTP/WS** to
  `kasm-workspaces_proxy_1:8080` (Kasm's internal 443 ssl listener still
  serves agent/guac traffic — both listeners are merged into one nginx conf).
- Secrets are derived per-install by umbrelOS entropy (`exports.sh` → the
  db password, manager token, registration token). Login for
  `admin@kasm.local` and `user@kasm.local` = the **Umbrel app password**
  shown in the app's Settings (App Password). Same password for both accounts.
- **Security:** `kasm_agent` mounts `/var/run/docker.sock` (root-equivalent
  Docker control) — inherent to Kasm (it spawns session containers) and why
  this is a community-store app, not an official one.

## 2. "Stuck at 99%" — decision tree (in order)

The config tree itself is verified good (generated on the build PC: every
generated YAML parses, nginx braces balanced). So a hang is in the
**install/start chain**, not a broken conf. umbrelOS 99% = images pulled,
compose up, but the app has not reported ready yet.

1. **Wait first.** The first boot runs `bootstrap` + `db-init` (alembic
   migrations + seeding 53 images) before any server starts, on top of the
   1.2 GB pull. 5–15 minutes at 99% is normal on slow disks/network. Check
   `mcp__umbrel__get_app_status`; if `state` is `ready` or
   `lastOperationFailure` is null, it simply finished — refresh the home
   screen.
2. **Still `starting` after ~20 min → the one-shot services are the usual
   suspect** (they `restart: on-failure`, so a failing one loops forever and
   everything behind it never starts):
   - Check completion markers over SSH (ask the user, or via their terminal):
     ```
     sudo ls -la /home/umbrel/umbrel/app-data/kasm-workspaces/data/kasm/
     ```
     Look for `.bootstrap-complete` and `.db-initialized`.
   - `.bootstrap-complete` **missing** → `bootstrap` failed. Restart the app
     from the umbrelOS home screen (Restart) — bootstrap is idempotent and
     retries cleanly. If it keeps failing, check its container logs (umbrelOS
     app status/logs view, or `docker logs kasm-workspaces_bootstrap_1` via
     SSH).
   - `.bootstrap-complete` present but `.db-initialized` **missing** → `db-init`
     failed. Check the db-init container logs for a python traceback. Common
     fixes: retry by removing ONLY the marker (leave everything else):
     ```
     sudo rm /home/umbrel/umbrel/app-data/kasm-workspaces/data/kasm/.db-initialized
     ```
     then Restart the app. (Same for `.bootstrap-complete` — removing it
     forces regeneration; that also re-rolls certs, which is fine on a
     fresh data tree but avoid on an already-working install.)
3. **Markers exist but the app never becomes reachable:** the proxy or
   gateway link is the problem.
   - Check `proxy` container logs for nginx config errors (the two vendor
     orchestrator confs were merged into one to avoid duplicate `map`
     errors — verified balanced, but the box may differ).
   - Verify the injected container name matches the gateway target:
     `APP_HOST: kasm-workspaces_proxy_1` (umbrelOS renames containers to
     `<app-id>_<service>_1`). If the store was subscribed before the app
     folder rename (it has always been `kasm-workspaces`), OK.
   - Verify the `kasm_default_network` docker network exists and the proxy
     is attached — session containers spawn onto it by that hardcoded name:
     ```
     sudo docker network ls | grep kasm
     sudo docker network inspect kasm_default_network | grep -A3 kasm-workspaces
     ```
4. **If the app actually FAILED (red/error, not 99%):** read the real error
   from `mcp__umbrel__get_app_status` (`lastOperationFailure`) or the
   notification — do not guess. Typical: image pull failure (registry
   hiccup, disk full) or compose-patch rejection; fix the cause, remove the
   app, re-add the store, reinstall. Removing an app wipes its app-data, so
   reinstall is a clean slate.

## 3. Verify it actually works (after ready)

1. Open the app from the home screen. Expect a **certificate warning** (that
   is umbrelOS's local HTTPS proxy) — proceed through it.
2. Sign in as `admin@kasm.local` (or `user@kasm.local`) with the Umbrel app
   password (app Settings → App Password / "Kasm Workspaces" app password).
3. Pick a workspace — e.g. **Firefox**. First launch pulls
   `kasmweb/firefox:1.19.0-rolling-daily` (1–2 GB) and can look frozen while
   it downloads. Confirm via SSH:
   ```
   docker images | grep -i firefox
   ```
4. The desktop should stream in the browser tab. If a session fails to
   start, check `kasm_agent` logs (image pull errors, docker.sock access,
   network attach failures) — and confirm the workspace image tag exists on
   Docker Hub (`kasmweb/*:1.19.0-rolling-daily` is the current rolling tag).

## 4. Do / don't

- **Do** use the umbrel MCP tools; they are the sanctioned way to see app
  state and failure reasons.
- **Don't** run `hermes update` or modify Hermes itself (umbrelOS manages it).
- **Don't** change the `exports.sh` secret names after install — they are
  derived from umbrelOS entropy; renaming breaks the DB password match.
- **Don't** wipe `data/kasm` on a working install to "clean up" — that resets
  all Kasm config, users and workspaces. Only remove specific markers when a
  one-shot genuinely failed (see step 2).
- **Don't** bulk-pull all workspace images; first-launch pull is by design.
- Sessions idle-logout after 20 minutes by default (admin can change it).
