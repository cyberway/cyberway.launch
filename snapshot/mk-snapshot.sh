#!/bin/bash

set -xe

error() {
   echo $1
   exit 1
}

[ "$EUID" -eq 0 ] || error "Please run as root"

CYBERWAY_VERSION=v2.1.1
PBZIP2=-pbzip2

NOW=`date +%Y%m%d`
SNAPSHOT_DIR=snapshot-$NOW-$CYBERWAY_VERSION

mkdir -p $SNAPSHOT_DIR

docker stop -t 120 state-reader || true
docker stop -t 120 nodeosd || true
./start_full_node.sh down

docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:rw -v cyberway-nodeos-data:/data:ro cyberway/cyberway:${CYBERWAY_VERSION}${PBZIP2} tar -c -Ipbzip2 -Pvf /host/nodeos.tar.bz2 /data
docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:rw -v cyberway-mongodb-data:/data:ro cyberway/cyberway:${CYBERWAY_VERSION}${PBZIP2} tar -c -Ipbzip2 -Pvf /host/mongodb.tar.bz2 /data

if [ `sudo docker volume ls -f name=cyberway-nats-data | wc -l` -eq 2 ]; then
    docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:rw -v cyberway-nats-data:/data:ro cyberway/cyberway:${CYBERWAY_VERSION}${PBZIP2} tar -c -Ipbzip2 -Pvf /host/nats.tar.bz2 /data
fi
