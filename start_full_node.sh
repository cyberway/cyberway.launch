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
    ( cd $CYBER_DATA; docker-compose -p cyberway -f $CYBER_COMPOSE_EVENTS down -t 120 || exit 1 )
    docker volume rm cyberway-mongodb-data
    docker volume rm cyberway-nodeos-data
    docker volume rm cyberway-queue
    docker volume rm cyberway-nats-data
    cyberway_rmdirs
    exit 0
elif [[ "$1" == "up" ]]; then
    ( cd $CYBER_DATA; docker-compose -p cyberway -f $CYBER_COMPOSE_EVENTS up -t 120 -d || exit 1 )
    exit 0
elif [[ "$1" == "down" ]]; then
    docker stop -t 120 nodeosd || true	
    ( cd $CYBER_DATA; docker-compose -p cyberway -f $CYBER_COMPOSE_EVENTS down -t 120 || exit 1 )
    exit 0
fi

cyberway_mkdirs
cyberway_check_available_space 314572800 300Gb
cyberway_download_genesis
cyberway_download_event_genesis
cyberway_add_full_config

echo "EXTRA_NODEOS_ARGS: $EXTRA_NODEOS_ARGS"

docker volume create cyberway-mongodb-data || true
docker volume create cyberway-nodeos-data || true
docker volume create cyberway-queue || true
docker volume create cyberway-nats-data || true

if [[ ( -z "$NATS_USER" ) || ( -z "$NATS_PASS" ) || ( -z "$MONGODB_EXPORTER_USER" ) || ( -z "$MONGODB_EXPORTER_PASS" ) ]]; then
    if [[ -f $CYBER_DATA/.env ]]; then
        if [[ $(grep -c '^\(MONGODB_EXPORTER\|NATS\)_\(USER\|PASS\)=[^\t\ ]\+' $CYBER_DATA/.env) != '4' ]]; then
            rm -f $CYBER_DATA/.env
        fi
    else
        rm -rf $CYBER_DATA/.env
    fi

    if [[ ! -f $CYBER_DATA/.env ]]; then
       NPASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
       NUSER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
       echo "NATS_USER=$NUSER" >> $CYBER_DATA/.env
       echo "NATS_PASS=$NPASS" >> $CYBER_DATA/.env
       echo "" >> $CYBER_DATA/.env
       echo "MONGODB_EXPORTER_USER=$NUSER" >> $CYBER_DATA/.env
       echo "MONGODB_EXPORTER_PASS=$NPASS" >> $CYBER_DATA/.env
    fi
fi

( cd $CYBER_DATA; docker-compose -p cyberway -f $CYBER_COMPOSE_EVENTS up -t 120 -d )
