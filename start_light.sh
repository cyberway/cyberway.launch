#!/bin/bash

set -xe

if [[ "$OSTYPE" == "darwin"* ]]; then
    brew install coreutils
    script_path=$(dirname $(greadlink -f $0))
else
    script_path=$(dirname $(readlink -f $0))
fi

. "$script_path/env.sh"

if [[ "$1" == "cleanup" ]]; then
    ( cd $CYBER_DATA; docker-compose -p cyberway -f $CYBER_COMPOSE down -t 120 || exit 1 )
    docker volume rm cyberway-mongodb-data
    docker volume rm cyberway-nodeos-data
    docker volume rm cyberway-queue
    cyberway_rmdirs
    exit 0
elif [[ "$1" == "up" ]]; then
    ( cd $CYBER_DATA; docker-compose -p cyberway -f $CYBER_COMPOSE up -t 120 -d || exit 1 )
    exit 0
elif [[ "$1" == "down" ]]; then
    ( cd $CYBER_DATA; docker-compose -p cyberway -f $CYBER_COMPOSE down -t 120 || exit 1 )
    exit 0
fi

cyberway_mkdirs
cyberway_check_available_space 10485760 10Gb
cyberway_download_genesis
cyberway_add_light_config

echo "EXTRA_NODEOS_ARGS: $EXTRA_NODEOS_ARGS"

docker volume create cyberway-mongodb-data || true
docker volume create cyberway-nodeos-data || true
docker volume create cyberway-queue || true

( cd $CYBER_DATA; docker-compose -p cyberway -f $CYBER_COMPOSE up -t 120 -d )
