# Kasm Workspaces for umbrelOS — bootstrap (first-run config generator)

# This is the equivalent of Kasm's install.sh config-generation step, run as a
# one-shot compose service. It vendors the 1.19.0 conf templates, generates
# per-install secrets/certs, and writes the /opt/kasm/current tree that every
# Kasm service mounts. Idempotent: a marker file skips regeneration on
# subsequent starts so certs/IDs are stable per install.

set -euo pipefail

KASM_INSTALL_BASE="/opt/kasm/current"
SRC="/opt/kasm-src"

ADMIN_PW="${KASM_ADMIN_PASSWORD:?need admin password}"
DB_PW="${KASM_DB_PASSWORD:?need db password}"
MANAGER_TOKEN="${KASM_MANAGER_TOKEN:?need manager token}"
REG_TOKEN="${KASM_REGISTRATION_TOKEN:?need registration token}"

# stable ids for one install (regenerated only when the tree is rebuilt)
SERVER_ID="$(cat /proc/sys/kernel/random/uuid)"

marker="${KASM_INSTALL_BASE}/.bootstrap-complete"
if [[ -f "${marker}" ]] && [[ -f "${KASM_INSTALL_BASE}/certs/kasm_nginx.crt" ]]; then
  echo "[bootstrap] already complete, skipping"
  exit 0
fi

echo "[bootstrap] generating Kasm config tree under ${KASM_INSTALL_BASE}"

mkdir -p "${KASM_INSTALL_BASE}"/{bin,certs,www,file_mappings/common,plugins,rolling}
mkdir -p "${KASM_INSTALL_BASE}/conf"/{nginx/services.d,nginx/containers.d,database/seed_data,app}
mkdir -p "${KASM_INSTALL_BASE}/tmp"/{api,kasm_db,manager,guac,rdpgw/var,rdpgw/tmp}
mkdir -p "${KASM_INSTALL_BASE}/log"/{nginx,logrotate,postgres}
mkdir -p "${KASM_INSTALL_BASE}/healthcheck"/{kasm_api,kasm_agent,kasm_manager,kasm_guac,rdp_gateway,rdp_https_gateway}

# ---- TLS certs (self-signed; internal use only; umbrelOS gateway does the browser TLS)
openssl req -x509 -nodes -days 1825 -newkey rsa:2048 \
  -keyout "${KASM_INSTALL_BASE}/certs/db_server.key" \
  -out "${KASM_INSTALL_BASE}/certs/db_server.crt" \
  -subj "/C=US/ST=VA/L=None/O=None/OU=DoFu/CN=localhost/emailAddress=none@none.none" 2>/dev/null
openssl req -x509 -nodes -days 1825 -newkey rsa:2048 \
  -keyout "${KASM_INSTALL_BASE}/certs/kasm_nginx.key" \
  -out "${KASM_INSTALL_BASE}/certs/kasm_nginx.crt" \
  -subj "/C=US/ST=VA/L=None/O=None/OU=DoFu/CN=localhost/emailAddress=none@none.none" 2>/dev/null
chmod 600 "${KASM_INSTALL_BASE}/certs/db_server.key" "${KASM_INSTALL_BASE}/certs/kasm_nginx.key"
chmod 600 "${KASM_INSTALL_BASE}/certs/db_server.crt" "${KASM_INSTALL_BASE}/certs/kasm_nginx.crt"

# ---- vendor config templates
cp -r "${SRC}/conf/app"/. "${KASM_INSTALL_BASE}/conf/app/"
cp "${SRC}/conf/database/data.sql" "${KASM_INSTALL_BASE}/conf/database/"
cp "${SRC}/conf/database/pg_hba.conf" "${KASM_INSTALL_BASE}/conf/database/"
cp "${SRC}/conf/database/postgresql.conf" "${KASM_INSTALL_BASE}/conf/database/"
cp -r "${SRC}/conf/database/seed_data"/. "${KASM_INSTALL_BASE}/conf/database/seed_data/"
cp "${SRC}/conf/nginx/resolver.conf" "${KASM_INSTALL_BASE}/conf/nginx/"
cp "${SRC}/conf/nginx/logging.conf" "${KASM_INSTALL_BASE}/conf/nginx/"
cp "${SRC}/conf/nginx/compress.conf" "${KASM_INSTALL_BASE}/conf/nginx/"
cp "${SRC}/conf/nginx/upstream_agent.conf" "${KASM_INSTALL_BASE}/conf/nginx/"
cp "${SRC}/conf/nginx/upstream_api.conf" "${KASM_INSTALL_BASE}/conf/nginx/"
cp "${SRC}/conf/nginx/upstream_manager.conf" "${KASM_INSTALL_BASE}/conf/nginx/"
cp -r "${SRC}/conf/nginx/services.d"/. "${KASM_INSTALL_BASE}/conf/nginx/services.d/"

# Merge both orchestrator variants into one file: the vendor ships
# orchestrator.conf (443 ssl, used by agent/guac internally) and
# orchestrator_http.conf (plain 8080, used by the umbrelOS gateway) with
# IDENTICAL map blocks — loading both would fail nginx on duplicate maps.
# Combined layout: maps once + ssl server block + http server block.
{
  awk 'NR<=27' "${SRC}/conf/nginx/orchestrator.conf"
  awk 'NR>=28' "${SRC}/conf/nginx/orchestrator.conf"
  awk 'NR>=28' "${SRC}/conf/nginx/orchestrator_http.conf"
} > "${KASM_INSTALL_BASE}/conf/nginx/orchestrator.conf"

chmod 600 "${KASM_INSTALL_BASE}/conf/database/pg_hba.conf" "${KASM_INSTALL_BASE}/conf/database/postgresql.conf"
chmod 777 "${KASM_INSTALL_BASE}/conf/nginx/containers.d"
chmod -R 755 "${KASM_INSTALL_BASE}/log" "${KASM_INSTALL_BASE}/healthcheck"

# ---- nginx: point certs at our tree (paths are hardcoded to /etc/ssl in templates)
sed -i 's#/etc/ssl/certs/kasm_nginx.crt#/opt/kasm/current/certs/kasm_nginx.crt#g; s#/etc/ssl/private/kasm_nginx.key#/opt/kasm/current/certs/kasm_nginx.key#g' \
  "${KASM_INSTALL_BASE}/conf/nginx/orchestrator.conf"

# single guac worker (upstream_guac.conf regenerated to match)
cat > "${KASM_INSTALL_BASE}/conf/nginx/upstream_guac.conf" <<'EOF'
upstream kasm_guac_backend {
  zone kasm_guac_zone 512k;
  server kasm_guac:3001 resolve;
}
EOF

# ---- api config
API="${KASM_INSTALL_BASE}/conf/app/api/api.app.config.yaml"
sed -i "s/^  password: changeme/  password: \"${DB_PW}\"/" "${API}"
sed -i "s/^  manager_id: null/  manager_id: $(cat /proc/sys/kernel/random/uuid)/" "${API}"
sed -i "s/^  server_id: null/  server_id: $(cat /proc/sys/kernel/random/uuid)/" "${API}"
sed -i "s/^  share_id: null/  share_id: $(cat /proc/sys/kernel/random/uuid)/" "${API}"
sed -i "s/^  server_hostname: null/  server_hostname: proxy/" "${API}"

# ---- agent config
AGENT="${KASM_INSTALL_BASE}/conf/app/agent/agent.app.config.yaml"
sed -i "s/^  server_id: .*/  server_id: ${SERVER_ID}/" "${AGENT}"
sed -i "s/^  token: .*/  token: \"${MANAGER_TOKEN}\"/" "${AGENT}"

# ---- guac config
GUAC="${KASM_INSTALL_BASE}/conf/app/guac/kasmguac.app.config.yaml"
sed -i "s/CLUSTER_SIZE/1/g" "${GUAC}"
sed -i "s/APIHOSTNAME/proxy/g" "${GUAC}"
sed -i "s/SERVER_ADDRESS/proxy/g" "${GUAC}"
sed -i "s/SERVER_PORT/443/g" "${GUAC}"
sed -i "s/ZONE/default/g" "${GUAC}"
sed -i "s/REGISTRATION_TOKEN/${REG_TOKEN}/g" "${GUAC}"

# ---- seed: default agents (server id must match agent config)
AGENTS="${KASM_INSTALL_BASE}/conf/database/seed_data/default_agents.yaml"
sed -i "s/00000000-0000-0000-0000-000000000000/${SERVER_ID}/" "${AGENTS}"

# ---- seed: default properties (users, tokens, zone port)
PROPS="${KASM_INSTALL_BASE}/conf/database/seed_data/default_properties.yaml"

# user password hashes: sha256(password + salt), same scheme as install.sh
ADMIN_SALT="$(cat /proc/sys/kernel/random/uuid)"
USER_SALT="$(cat /proc/sys/kernel/random/uuid)"
ADMIN_HASH="$(printf '%s%s' "${ADMIN_PW}" "${ADMIN_SALT}" | sha256sum | cut -c-64)"
USER_HASH="$(printf '%s%s' "${ADMIN_PW}" "${USER_SALT}" | sha256sum | cut -c-64)"

# admin@kasm.local (hash e3b0c4... = sha256 of empty string in template)
sed -i "s/^  pw_hash: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855/  pw_hash: ${ADMIN_HASH}/" "${PROPS}"
sed -i "s/^  salt: \"\${uuid:user_salt:1}\"/  salt: \"${ADMIN_SALT}\"/" "${PROPS}"
# user@kasm.local (hash ef812e...)
sed -i "s/^  pw_hash: ef812e6cd523e95742921d31bd61856c62a14d76b03d422bc528f0fe37c8187d/  pw_hash: ${USER_HASH}/" "${PROPS}"
sed -i "s/^  salt: \"\${uuid:user_salt:2}\"/  salt: \"${USER_SALT}\"/" "${PROPS}"

# settings: manager token + component registration token
sed -i "s/value: \"\${random_token:manager_token}\"/value: \"${MANAGER_TOKEN}\"/" "${PROPS}"
sed -i "s/value: \"\${random_token:registration_token}\"/value: \"${REG_TOKEN}\"/" "${PROPS}"

# zone: browser-facing port (umbrelOS app port) + proxy auth address
sed -i "s/^  proxy_port: 443/  proxy_port: ${KASM_PROXY_PORT:-8443}/" "${PROPS}"
sed -i 's/upstream_auth_address: \$request_host\$/upstream_auth_address: proxy/' "${PROPS}"
# logging port follows the browser port
sed -i "/^  name: log_port$/,/^  value_type: int$/ s/^  value: '443'/  value: '${KASM_PROXY_PORT:-8443}'/" "${PROPS}"

# ---- ownership
# everything kasm (uid 1000 = umbrelOS app-data owner); postgres bits to uid 70
chown -R 1000:1000 "${KASM_INSTALL_BASE}"
chown -R 70:70 "${KASM_INSTALL_BASE}/conf/database" "${KASM_INSTALL_BASE}/certs/db_server.key" "${KASM_INSTALL_BASE}/certs/db_server.crt" "${KASM_INSTALL_BASE}/log/postgres" "${KASM_INSTALL_BASE}/tmp/kasm_db"

touch "${marker}"
echo "[bootstrap] complete"
