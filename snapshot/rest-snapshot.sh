#!/bin/bash

set -xe

SNAPSHOT_DIR=$1
CYBERWAY_VERSION=v2.1.1

error() {
   echo $1
   exit 1
}

[ "$EUID" -eq 0 ] || error "Please run as root"
[ "x$SNAPSHOT_DIR" != "x" ] || error "SNAPSHOT_DIR is not defined"
[ -f "$SNAPSHOT_DIR"/nodeos.tar.bz2 ] || error "no nodeos.tar.bz2"
[ -f "$SNAPSHOT_DIR"/mongodb.tar.bz2 ] || error "no mongodb.tar.bz2"

docker stop -t 120 state-reader || true
docker stop -t 120 nodeosd || true
./start_full_node.sh down || true

docker volume rm cyberway-nodeos-data || true
docker volume create cyberway-nodeos-data || true

docker volume rm cyberway-mongodb-data || true
docker volume create cyberway-mongodb-data || true

docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:ro -v cyberway-nodeos-data:/data:rw cyberway/cyberway:$CYBERWAY_VERSION tar -xPvf /host/nodeos.tar.bz2
docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:ro -v cyberway-mongodb-data:/data:rw cyberway/cyberway:$CYBERWAY_VERSION tar -xPvf /host/mongodb.tar.bz2

if [ -f "$SNAPSHOT_DIR"/nats.tar.bz2 ]; then
    docker volume rm cyberway-nats-data || true
    docker volume create cyberway-nats-data || true

    docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:ro -v cyberway-nats-data:/data:rw cyberway/cyberway:$CYBERWAY_VERSION tar -xPvf /host/nats.tar.bz2
fi
