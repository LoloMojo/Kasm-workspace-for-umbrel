# Per-install secrets for Kasm Workspaces, derived deterministically from
# umbrelOS's per-app entropy so they survive restarts but differ per device.
# db password must match POSTGRES_PASSWORD in docker-compose.yml, and the
# bootstrap container writes the same values into the Kasm config tree.

export APP_KASM_WORKSPACES_DB_PASSWORD="$(derive_entropy "${app_entropy_identifier}-db-password")"
export APP_KASM_WORKSPACES_MANAGER_TOKEN="$(derive_entropy "${app_entropy_identifier}-manager-token")"
export APP_KASM_WORKSPACES_REGISTRATION_TOKEN="$(derive_entropy "${app_entropy_identifier}-registration-token")"
