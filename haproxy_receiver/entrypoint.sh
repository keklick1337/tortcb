#!/usr/bin/env bash
# ===============================================================
# Project Name: Tor TCP Chain Balancer
# Author: keklick1337 https://github.com/keklick1337/tortcb
# Date: 4 February 2025
# ===============================================================

set -e

# This file launches multiple local Tor clients (one per onion domain:port),
# then starts a socat listener for each domain, and finally configures HAProxy
# to load-balance traffic across these local ports.

DOMAINS_FILE="/etc/domains.list"    # The file containing lines like "onion:port"
TOR_BASE_DIR="/var/lib/tor_clients" # Directory to store each Tor client's DataDirectory
HAPROXY_TEMPLATE="/etc/haproxy/haproxy.cfg.template"
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"

LISTEN_PORT="${HAPROXY_LISTEN_PORT:-80}"
STATS_PORT="${STATS_PORT:-9090}"
STATS_USER="${STATS_USER:-admin}"
STATS_PASS="${STATS_PASS:-adminpass}"

BASE_LOCAL_PORT="${BASE_LOCAL_PORT:-30000}"
BASE_SOCKS_PORT="${BASE_SOCKS_PORT:-9050}"

if [ ! -f "${DOMAINS_FILE}" ]; then
  echo "ERROR: domains.list not found at ${DOMAINS_FILE}"
  exit 1
fi

mkdir -p "${TOR_BASE_DIR}"
chown -R haproxyuser:haproxyuser "${TOR_BASE_DIR}"
chmod 700 "${TOR_BASE_DIR}"

BACKEND_SERVERS=""

i=0

echo "Reading domains.list from ${DOMAINS_FILE}..."

while IFS= read -r line; do
  # Skip empty lines
  [ -z "${line}" ] && continue
  i=$((i + 1))

  onion="${line%:*}"
  onion_port="${line#*:}"

  # For the i-th domain, we create a SocksPort = BASE_SOCKS_PORT + i - 1
  socks_port=$((BASE_SOCKS_PORT + i - 1))
  # Then we create a local socat listener = BASE_LOCAL_PORT + i - 1
  local_port=$((BASE_LOCAL_PORT + i - 1))

  echo "== Domain #${i}: ${onion}:${onion_port}"
  echo "   Tor SocksPort = ${socks_port}"
  echo "   Socat local port = ${local_port}"

  # Create a directory for the i-th Tor client
  INSTANCE_DIR="${TOR_BASE_DIR}/tor_client_${i}"
  mkdir -p "${INSTANCE_DIR}"
  chown -R haproxyuser:haproxyuser "${INSTANCE_DIR}"
  chmod 700 "${INSTANCE_DIR}"

  # Generate a minimal torrc
  cat <<EOF > "${INSTANCE_DIR}/torrc"
ControlPort 0
SocksPort ${socks_port}
DataDirectory ${INSTANCE_DIR}
Log notice stdout
EOF

  echo "Starting Tor instance #${i} with SocksPort=${socks_port}..."
  # Run Tor as haproxyuser so it doesn't attempt setgid
  su -s /bin/sh -c "tor -f '${INSTANCE_DIR}/torrc' \
    --RunAsDaemon 1 \
    --PidFile '${INSTANCE_DIR}/tor.pid'" haproxyuser

  # Now launch socat in the background to forward traffic via SOCKS4A to onion
  echo "Starting socat listener on ${local_port} => SOCKS4A(127.0.0.1:${onion_port},socksport=${socks_port})"
  nohup socat TCP-LISTEN:${local_port},fork,reuseaddr SOCKS4A:127.0.0.1:${onion}:${onion_port},socksport=${socks_port} &

  # Add a server line to HAProxy config
  BACKEND_SERVERS="${BACKEND_SERVERS}    server onion${i} 127.0.0.1:${local_port} check
"
done < "${DOMAINS_FILE}"

echo "Generating HAProxy config..."
cp "${HAPROXY_TEMPLATE}" "${HAPROXY_CFG}"

sed -i "s/%%LISTEN_PORT%%/${LISTEN_PORT}/g" "${HAPROXY_CFG}"
sed -i "s/%%STATS_PORT%%/${STATS_PORT}/g" "${HAPROXY_CFG}"
sed -i "s/%%STATS_USER%%/${STATS_USER}/g" "${HAPROXY_CFG}"
sed -i "s/%%STATS_PASS%%/${STATS_PASS}/g" "${HAPROXY_CFG}"

sed -i "/%%BACKEND_SERVERS%%/r /dev/stdin" "${HAPROXY_CFG}" <<< "${BACKEND_SERVERS}"
sed -i "/%%BACKEND_SERVERS%%/d" "${HAPROXY_CFG}"

echo "Final HAProxy configuration:"
cat "${HAPROXY_CFG}"

echo "Starting HAProxy on port ${LISTEN_PORT} (stats on ${STATS_PORT})..."
exec haproxy -f "${HAPROXY_CFG}" -db
