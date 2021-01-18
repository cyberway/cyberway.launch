#!/bin/bash

set -xe

if [[ "$OSTYPE" == "darwin"* ]]; then
    brew install coreutils
    script_path=$(dirname $(greadlink -f $0))
else
    script_path=$(dirname $(readlink -f $0))
fi

. "$script_path/../env.sh"

CYBERWAY_VERSION=v2.1.1
PBZIP2=-pbzip2

NOW=`date +%Y%m%d`
SNAPSHOT_DIR=snapshot-$NOW-$CYBERWAY_VERSION

mkdir -p $SNAPSHOT_DIR

docker stop -t 120 state-reader || true
docker stop -t 120 nodeosd || true

if [ -f $CYBER_COMPOSE_EVENTS ]; then
    "$script_path/../start_full_node.sh" down
elif [ -f CYBER_COMPOSE ]; then
    "$script_path/../start_light.sh" down
fi

docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:rw -v cyberway-nodeos-data:/data:ro cyberway/cyberway:${CYBERWAY_VERSION}${PBZIP2} tar -c -Ipbzip2 -Pvf /host/nodeos.tar.bz2 /data
docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:rw -v cyberway-mongodb-data:/data:ro cyberway/cyberway:${CYBERWAY_VERSION}${PBZIP2} tar -c -Ipbzip2 -Pvf /host/mongodb.tar.bz2 /data

if [ -f $CYBER_COMPOSE_EVENTS ]; then
    docker run --rm -ti -v `readlink -f $SNAPSHOT_DIR`:/host:rw -v cyberway-nats-data:/data:ro cyberway/cyberway:${CYBERWAY_VERSION}${PBZIP2} tar -c -Ipbzip2 -Pvf /host/nats.tar.bz2 /data
fi

docker start state-reader || true

if [ -f $CYBER_COMPOSE_EVENTS ]; then
    "$script_path/../start_full_node.sh"
elif [ -f $CYBER_COMPOSE ]; then
    "$script_path/../start_light.sh"
else
    echo "No information about the node type"
fi
