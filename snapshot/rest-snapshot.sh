#!/bin/bash

set -xe

if [[ "$OSTYPE" == "darwin"* ]]; then
    brew install coreutils
    script_path=$(dirname $(greadlink -f $0))
else
    script_path=$(dirname $(readlink -f $0))
fi

. "$script_path/../env.sh"

SNAPSHOT_DIR=$1
CYBERWAY_VERSION=v2.1.1
PBZIP2=-pbzip2

error() {
   echo $1 >&2
   exit 1
}

[ "x$SNAPSHOT_DIR" != "x" ] || error "SNAPSHOT_DIR is not defined"
[ -f "$SNAPSHOT_DIR"/nodeos.tar.bz2 ] || error "no nodeos.tar.bz2"
[ -f "$SNAPSHOT_DIR"/mongodb.tar.bz2 ] || error "no mongodb.tar.bz2"

docker stop -t 120 state-reader || true
docker stop -t 120 nodeosd || true

if [ -f $CYBER_COMPOSE_EVENTS ]; then
    "$script_path/../start_full_node.sh" down
elif [ -f CYBER_COMPOSE ]; then
    "$script_path/../start_light.sh" down
fi

docker volume rm cyberway-nodeos-data || true
docker volume create cyberway-nodeos-data || true

docker volume rm cyberway-mongodb-data || true
docker volume create cyberway-mongodb-data || true

docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:ro -v cyberway-nodeos-data:/data:rw cyberway/cyberway:${CYBERWAY_VERSION}${PBZIP2} tar -x -Ipbzip2 -Pvf /host/nodeos.tar.bz2
docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:ro -v cyberway-mongodb-data:/data:rw cyberway/cyberway:${CYBERWAY_VERSION}${PBZIP2} tar -x -Ipbzip2 -Pvf /host/mongodb.tar.bz2

if [ -f "$SNAPSHOT_DIR"/nats.tar.bz2 ]; then
    docker volume rm cyberway-nats-data || true
    docker volume create cyberway-nats-data || true

    docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:ro -v cyberway-nats-data:/data:rw cyberway/cyberway:${CYBERWAY_VERSION}${PBZIP2} tar -x -Ipbzip2 -Pvf /host/nats.tar.bz2
fi

if [ -f $CYBER_COMPOSE_EVENTS ]; then
    "$script_path/../start_full_node.sh"
elif [ -f $CYBER_COMPOSE ]; then
    "$script_path/../start_light.sh"
else
    echo "No information about the node type" >&2
fi
