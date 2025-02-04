#!/usr/bin/env bash
# ===============================================================
# Project Name: Tor TCP Chain Balancer
# Author: keklick1337 https://github.com/keklick1337/tortcb
# Date: 4 February 2025
# ===============================================================

set -e

# This script creates multiple Tor hidden services, each mapping a random onion port
# to an existing host service (HOST_IP:HOST_PORT). The list of generated addresses
# is stored in domains.list.

HOST_IP="${HOST_IP:-host.docker.internal}"
HOST_PORT="${HOST_PORT:-5000}"
TOR_INSTANCES="${TOR_INSTANCES:-3}"
TOR_DATA_DIR="${TOR_DATA_DIR:-/var/lib/tor/hidden_services}"
RANDOM_PORT_START="${RANDOM_PORT_START:-20000}"

DOMAINS_LIST_FILE="${TOR_DATA_DIR}/domains.list"

mkdir -p /etc/tor/instances
chown -R toruser:toruser /etc/tor/instances

mkdir -p "${TOR_DATA_DIR}"
chown -R toruser:toruser "${TOR_DATA_DIR}"
chmod 700 "${TOR_DATA_DIR}"

rm -f "${DOMAINS_LIST_FILE}" || true
touch "${DOMAINS_LIST_FILE}"

echo "$(date +'%Y-%m-%d %H:%M:%S') Creating ${TOR_INSTANCES} Tor hidden services, forwarding host: ${HOST_IP}:${HOST_PORT}..."

for i in $(seq 1 "${TOR_INSTANCES}"); do
  INSTANCE_DIR="/etc/tor/instances/tor${i}"
  mkdir -p "${INSTANCE_DIR}"
  chown -R toruser:toruser "${INSTANCE_DIR}"
  chmod 700 "${INSTANCE_DIR}"

  HSDIR="${TOR_DATA_DIR}/instance${i}"
  mkdir -p "${HSDIR}"
  chown -R toruser:toruser "${HSDIR}"
  chmod 700 "${HSDIR}"

  cp /etc/tor/torrc.template "${INSTANCE_DIR}/torrc"

  # Determine the onion port
  ONION_PORT=$((RANDOM_PORT_START + i - 1))

  {
    echo "HiddenServiceDir ${HSDIR}"
    echo "HiddenServicePort ${ONION_PORT} ${HOST_IP}:${HOST_PORT}"
  } >> "${INSTANCE_DIR}/torrc"

  echo "$(date +'%Y-%m-%d %H:%M:%S') Tor instance ${i}: HiddenServicePort ${ONION_PORT} -> ${HOST_IP}:${HOST_PORT}"

  su -s /bin/sh -c "tor -f '${INSTANCE_DIR}/torrc' \
    --RunAsDaemon 1 \
    --DataDirectory '${INSTANCE_DIR}' \
    --PidFile '${INSTANCE_DIR}/tor.pid'" toruser
done

sleep 5

echo "$(date +'%Y-%m-%d %H:%M:%S') Collecting onion hostnames..."
for i in $(seq 1 "${TOR_INSTANCES}"); do
  HOSTNAME_FILE="${TOR_DATA_DIR}/instance${i}/hostname"
  if [ -f "${HOSTNAME_FILE}" ]; then
    PORT=$((RANDOM_PORT_START + i - 1))
    ONION="$(cat "${HOSTNAME_FILE}")"
    echo "${ONION}:${PORT}" >> "${DOMAINS_LIST_FILE}"
    echo "Instance ${i}: ${ONION}:${PORT}"
  else
    echo "WARNING: no hostname file for instance ${i}"
  fi
done

echo "domains.list => ${DOMAINS_LIST_FILE}"
tail -f /dev/null
