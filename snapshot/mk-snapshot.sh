#!/bin/bash

set -xe

CYBERWAY_VERSION=v2.1.1

NOW=`date +%Y%m%d`
SNAPSHOT_DIR=snapshot-$NOW-$CYBERWAY_VERSION

mkdir -p $SNAPSHOT_DIR

sudo docker stop -t 120 state-reader || true
sudo docker stop -t 120 nodeosd || true
sudo ./start_full_node.sh down

sudo docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:rw -v cyberway-nodeos-data:/data:ro cyberway/cyberway:$CYBERWAY_VERSION tar -cPvf /host/nodeos.tar /data
sudo docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:rw -v cyberway-mongodb-data:/data:ro cyberway/cyberway:$CYBERWAY_VERSION tar -cPvf /host/mongodb.tar /data
sudo docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:rw -v cyberway-nats-data:/data:ro cyberway/cyberway:$CYBERWAY_VERSION tar -cPvf /host/nats.tar /data
