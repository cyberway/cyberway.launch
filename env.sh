CYBER_IMAGE="cyberway/cyberway:$cyberway_branch"
CYBER_ETC="/etc/cyberway"
CYBER_DATA="/var/lib/cyberway"
CYBER_CONFIG="$CYBER_ETC/config.ini"
CYBER_GENESIS="$CYBER_DATA/genesis-data"
CYBER_COMPOSE="$CYBER_DATA/docker-compose.yml"
CYBER_COMPOSE_EVENTS="$CYBER_DATA/docker-compose-events.yml"
CYBER_LAUNCH_URL='https://raw.githubusercontent.com/cyberway/cyberway.launch/master'
CYBER_EVENT_GENESIS="$CYBER_GENESIS/event-genesis"
CYBER_EVENT_GENESIS_URL="https://download.cyberway.io/ee-genesis-10-09-2019.tar.bz2"

cyberway_check_available_space() {
    local dir=$(dirname "$CYBER_DATA")
    local avail=$(df $dir --output=avail | tail -n +2)
    local min_size=$1
    local txt_min_size=$2

    [ "$avail" -ge $min_size  ] || \
    { echo "ERROR: Not enough available disk space at $1. It's need at least $2 free."; exit 1; }
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

cyberway_rmdirs() {
    rm -rf "$CYBER_ETC"
    rm -rf "$CYBER_DATA"
    rm -rf "$CYBER_GENESIS"
}

cyberway_mkdirs() {
    check_or_create_directory "$CYBER_ETC"
    check_or_create_directory "$CYBER_DATA"
}

cyberway_download_genesis() {
    echo "Download CyberWay genesis."

    check_or_create_directory "$CYBER_GENESIS"
    [ ! -f $CYBER_GENESIS/'genesis.json' ] || [ ! -f $CYBER_GENESIS/'genesis.dat' ] || return 0

    rm -f $CYBER_GENESIS/'genesis.json' || true
    rm -f $CYBER_GENESIS/'genesis.dat' || true

    local genesis_data_url=$(curl --silent $CYBER_LAUNCH_URL'/genesis-data.link')

    curl $CYBER_LAUNCH_URL'/genesis.json'  --output $CYBER_GENESIS'/genesis.json'
    curl "$genesis_data_url" --output "$CYBER_GENESIS/genesis.dat"
}

cyberway_download_event_genesis() {
    local event_genesis_files="accounts.dat funds.dat balance_conversions.dat \
          witnesses.dat delegations.dat messages.dat pinblocks.dat transfers.dat \
          rewards.dat withdraws.dat contracts.dat"

    check_or_create_directory "$CYBER_EVENT_GENESIS"

    for file in $event_genesis_files; do
        if [[ ! -f "$CYBER_EVENT_GENESIS/$file" ]]; then
            [ -f "$CYBER_EVENT_GENESIS/ee-genesis-data.tar.bz2" ] || curl "$CYBER_EVENT_GENESIS_URL" --output "$CYBER_EVENT_GENESIS/ee-genesis-data.tar.bz2"
            tar -xvf "$CYBER_EVENT_GENESIS/ee-genesis-data.tar.bz2" -C "$CYBER_EVENT_GENESIS"
            break
        fi
    done

    for file in $event_genesis_files; do
        EXTRA_NODEOS_ARGS+=" --event-engine-genesis=/opt/cyberway/bin/genesis-data/event-genesis/$file"
    done
    export EXTRA_NODEOS_ARGS
}

add_p2p_nodes() {
    echo "Add public p2p addresses to CyberWay config"

    for ip in $(curl --silent $CYBER_LAUNCH_URL'/seednodes'); do
        [ -z "$ip" ] || add_config_value 'p2p-peer-address' $ip $CYBER_CONFIG
    done
}

cyberway_add_light_config() {
    cp config.ini $CYBER_CONFIG
    cp docker-compose.yml $CYBER_DATA

    add_p2p_nodes
}

cyberway_add_full_config() {
    cp config.ini $CYBER_CONFIG
    cp docker-compose-events.yml $CYBER_DATA
    cp -R nats $CYBER_DATA
    cp -R mongodb-exporter $CYBER_DATA

    add_p2p_nodes
}
