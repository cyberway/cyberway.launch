#!/bin/bash

set -xe

cyberway_branch="v2.0.3"

CYBER_IMAGE="cyberway/cyberway:$cyberway_branch"
CYBER_ETC="/etc/cyberway"
CYBER_DATA="/var/lib/cyberway"
CYBER_CONFIG="$CYBER_ETC/config.ini"
CYBER_GENESIS="$CYBER_DATA/genesis-data"
CYBER_COMPOSE="$CYBER_DATA/docker-compose.yml"
CYBER_LAUNCH_URL='https://raw.githubusercontent.com/cyberway/cyberway.launch/master'

check_available_space() {
    local avail=$(df $1 --output=avail | tail -n +2)

    [ "$avail" -ge 10485760 ] || \
    { echo "ERROR: Not enough available disk space at $1. It's need at least 10Gb free."; exit 1; }
}

check_or_create_directory() {
    local dir=$1

    mkdir -p "$dir"
    [ -d "$dir" -a -w "$dir" ] || { echo "Directory "$dir" missing or disabled write-access"; exit 1; }
}

remove_trailing_comments() {
    local key=$1
    local config=$2

    sed -i 's|^\([ \t]*'$key'[ \t]*=[^#]*\)#.*|\1|' $config
}

add_config_value() {
    local key=$1
    local value=$2
    local config=$3

    remove_trailing_comments $key $config

    if [ $(grep -cP '^[ \t]*'$key'[ \t]*=[ \t]*'$value'[ \t]*$' $config) == '0' ]; then
        sed -i '1i '$key' = '$value $config
    fi
}

cyberway_prestart_check() {
    check_or_create_directory "$CYBER_ETC"
    check_or_create_directory "$CYBER_DATA"
    check_or_create_directory "$CYBER_GENESIS"

    check_available_space $(dirname "$CYBER_DATA")

    docker pull $CYBER_IMAGE
}

cyberway_download_genesis() {
    echo "Download CyberWay genesis."

    rm -rf $CYBER_GENESIS || true
    mkdir -p $CYBER_ETC $CYBER_DATA $CYBER_GENESIS

    local genesis_data_url=$(curl --silent $CYBER_LAUNCH_URL'/genesis-data.link')

    curl $CYBER_LAUNCH_URL'/genesis.json'  --output $CYBER_GENESIS'/genesis.json'
    curl "$genesis_data_url" --output "$CYBER_GENESIS/genesis.dat"
}

cyberway_add_p2p_nodes() {
    echo "Add public p2p addresses to CyberWay config"

    for ip in $(curl --silent $CYBER_LAUNCH_URL'/seednodes'); do
        [ -z "$ip" ] || add_config_value 'p2p-peer-address' $ip $CYBER_CONFIG
    done
}

cyberway_first_run() {
    echo "Get last version of CyberWay and run it with genesis."

    [ -f "$CYBER_GENESIS/genesis.json" -a -f "$CYBER_GENESIS/genesis.dat" ] || { echo "No genesis for CyberWay"; exit 1; }

    docker pull $CYBER_IMAGE

    cp config.ini $CYBER_CONFIG
    cyberway_add_p2p_nodes

    sed "s|image: cyberway/cyberway:stable|image: $CYBER_IMAGE|g" <docker-compose.yml >$CYBER_COMPOSE

    docker stop keosd nodeosd mongo || true
    docker rm keosd nodeosd mongo || true

    for v in cyberway-keosd-data cyberway-mongodb-data cyberway-nodeos-data; do
        docker volume rm $v || true
        docker volume create --name $v
    done

    ( cd $CYBER_DATA; docker-compose -p cyberway -f $CYBER_COMPOSE up -t 120 -d )
}

cyberway_prestart_check
cyberway_download_genesis
cyberway_first_run
