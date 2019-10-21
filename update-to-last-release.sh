#!/bin/bash

set -xe

SRC_CYBERWAY_COMPOSE=https://raw.githubusercontent.com/cyberway/cyberway.launch/master/docker-compose.yml

CYBERWAY_DATA_PATH=/var/lib/cyberway
CYBERWAY_ETC_PATH=/etc/cyberway
DST_CYBERWAY_COMPOSE="${CYBERWAY_DATA_PATH}/docker-compose.yml"

cp "${DST_CYBERWAY_COMPOSE}"{,.bk}
curl "${SRC_CYBERWAY_COMPOSE}" --output "${DST_CYBERWAY_COMPOSE}"

CYBERWAY_IMAGE=$(awk '/image: cyberway\/cyberway/ {print $2}' "${DST_CYBERWAY_COMPOSE}")
docker pull "${CYBERWAY_IMAGE}"

( cd "${CYBERWAY_DATA_PATH}"; docker-compose -p cyberway -f "${DST_CYBERWAY_COMPOSE}" up -t 120 -d )

