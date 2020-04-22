#!/bin/bash

set -xe

get_config_value() {
    local key=$1
    local config=$2

    awk -F "[ \t]*=[ \t]*" '{ if ($1=="'$key'") print $2; }' $config
}

remove_trailing_comments() {
    local key=$1
    local config=$2

    sed -i 's|^\([ \t]*'$key'[ \t]*=[^#]*\)#.*|\1|' $config
}

set_config_value() {
    local key=$1
    local value=$2
    local config=$3

    if [ $(grep -cP '^[ \t]*'$key'[ \t]*=' $config) != '0' ]; then
        # existing value
        sed -i 's|^[ \t]*'$key'[ \t]*=.*|'$key' = '$value'|g' $config
    elif [ $(grep -cP '^[ \t]*#[ \t]*'$key'[ \t=#]' $config) != '0' ]; then
        # commented value
        sed -i 's|^[ \t]*#[ \t]*'$key'[ \t]*=.*|'$key' = '$value'|g' $config
    else
        # not existing value
        sed -i '1i '$key' = '$value $config
    fi
}

append_config_value() {
    local key=$1
    local value=$2
    local config=$3

    remove_trailing_comments $key $config

    if [ $(grep -cP '^[ \t]*'$key'[ \t]*=[a-zA-Z1-9_ \t]*'$value'[ \t]?' $config) == '0' ]; then
        sed -i 's|^[ \t]*'$key'[ \t]*=.*|& \'$value'|' $config
    fi
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

remove_config_value() {
    local key=$1
    local value=$2
    local config=$3

    if [ -z "$value" ]; then
        sed -i '/^[ \t]*'$key'[ \t]*=.*/d' $config
    else
        remove_trailing_comments $key $config
        sed -i '/^[ \t]*'$key'[ \t]*=[ \t]*'$value'[ \t]*$/d' $config
    fi
}

goloschain_wait_transit() {
    echo "Wait transit complete."
    while [ ! -f $STATE_DUMP'.map' ]; do
        sleep 60
    done

    sleep 180

    echo "Transit is complete"
}

launch_wait_transit() {
    echo "Wait transit complete."
    while [ $(curl --output /dev/null --silent --head --fail $CYBER_LAUNCH_URL'/cyberway.start') ]; do
        sleep 60
    done

    echo "Transit is complete"
}

get_hf_version() {
    curl --data '{"method":"call", "params": ["database_api", "get_hardfork_version",[]],"jsonrpc":"2.0","id":0}' http://$goloschain_ip:8090/rpc | \
        python -mjson.tool | awk '/result/ {print substr($2, 4, 2) }'
}

goloschain_wait_hf21() {
    echo "Wait HF-21."

    while [ $(get_hf_version) != "21" ]; do
        sleep 60
    done

    sleep 60

    echo "HF-21 is active."
}

cyberway_generate_genesis() {
    echo "Get last version of Golos DApp."
    echo "Generate genesis."

    [ -f $STATE_DUMP ] || { echo "No GolosChain state to generate genesis for CyberWay"; exit 1; }

    rm -rf $CYBER_GENESIS || true
    mkdir -p $CYBER_ETC $CYBER_DATA $CYBER_GENESIS
    docker stop $GOLOS_NAME || true

    docker pull $DAPP_IMAGE

    (
        export GOLOS_STATE=$STATE_DUMP GOLOS_IMAGE=$DAPP_IMAGE DEST=$CYBER_GENESIS
        export GENESIS_JSON_TMPL=genesis.json.tmpl GENESIS_INFO_TMPL=genesis-info.json.tmpl
        [ "$DAPP_API_NODE" -a -d "$STATE_OPDUMP" ] && export GOLOS_OP_STATE=$STATE_OPDUMP
        ./create-genesis.sh
    )
}

cyberway_download_genesis() {
    echo "Download CyberWay genesis."

    rm -rf $CYBER_GENESIS || true
    mkdir -p $CYBER_ETC $CYBER_DATA $CYBER_GENESIS

    local genesis_data_url=$(curl --silent $CYBER_LAUNCH_URL'/genesis-data.link')

    curl $CYBER_LAUNCH_URL'/genesis.json'  --output $CYBER_GENESIS'/genesis.json'
    curl "$genesis_data_url" --output "$CYBER_GENESIS/genesis.dat"
}

convert_username_to_account() {
    convert_script='
import hashlib
import sys

def name_to_string(name):
    charmap = "12345abcdefghijklmnopqrstuvwxyz"
    account = ""
    value = 0
    h = hashlib.sha1(name.encode()).digest()
    for i in range(0,8):
        value += h[i]<<(i*8)
    for i in range(0,12):
        account += charmap[value%31]
        value //= 31
    return account

print(name_to_string(sys.argv[1]))
'
    python3 -c "$convert_script" $1
}

cyberway_set_witness() {
    local config=$1

    [ -z "$WITNESS" ] || ( [ "$WITNESS" ] && [ "$SIGNING_KEY" ] ) || { echo "Need to set SIGNING_KEY when WITNESS set"; exit 1; }
    local witness=${WITNESS:-$(get_config_value "witness" $GOLOS_CONFIG | sed 's/"//g')}
    if [ "$witness" ]; then
        local account=${WITNESS:-$(convert_username_to_account $witness)}
        local priv_key=${SIGNING_KEY:-$(get_config_value "private-key" $GOLOS_CONFIG)}
        local pub_key=$(docker run --rm -ti $CYBER_IMAGE bash -c \
            "export PATH=$PATH:/opt/cyberway/bin; cleos wallet create --to-console && cleos wallet import --private-key $priv_key" \
            | awk '/imported private key for: (GLS.*)/{split($5,parts,/[\r\n]/);print parts[1];}')

        [ "$pub_key" ] || { echo "Can't extract public key from \"$priv_key\""; exit 1; }

        if [ "$config" ]; then
            set_config_value 'producer-name' $account $config
            set_config_value 'signature-provider' "$pub_key=KEY:$priv_key" $config
        fi

        echo "INFO: Witness \"$witness\" (account \"$account\") with key $pub_key"
    else
        echo "WARN: Witness not found" >&2
    fi
}

cyberway_first_run() {
    echo "Get last version of CyberWay and run it with genesis."

    [ -f "$CYBER_GENESIS/genesis.json" -a -f "$CYBER_GENESIS/genesis.dat" ] || { echo "No genesis for CyberWay"; exit 1; }

    docker pull $CYBER_IMAGE

    cp config.ini $CYBER_CONFIG
    cyberway_set_witness $CYBER_CONFIG
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

state_prestart_check() {
    check_or_create_directory $(dirname "$STATE_DUMP")
    check_or_create_directory "$STATE_OPDUMP"

    check_available_space "$GOLOS_DATA"

    docker pull $DAPP_IMAGE
}

cyberway_prestart_check() {
    check_or_create_directory "$CYBER_ETC"
    check_or_create_directory "$CYBER_DATA"
    check_or_create_directory "$CYBER_GENESIS"

    check_available_space $(dirname "$CYBER_DATA")

    # Check witness and signing_key
    cyberway_set_witness

    docker pull $CYBER_IMAGE
}

cyberway_clear_p2p_nodes() {
    echo "Remove p2p addresses from CyberWay config"

    remove_config_value 'p2p-peer-address' '' $CYBER_CONFIG
}

cyberway_add_p2p_nodes() {
    echo "Add public p2p addresses to CyberWay config"

    for ip in $(curl --silent $CYBER_LAUNCH_URL'/seednodes'); do
        [ -z "$ip" ] || add_config_value 'p2p-peer-address' $ip $CYBER_CONFIG
    done
}

send_cliwallet_commands() {
    if [ ! -f $GOLOS_WALLET ]; then
        local privatekey=${SIGNING_KEY:-$(get_config_value "private-key" $GOLOS_CONFIG)}
        docker exec -ti $GOLOS_NAME "/usr/local/bin/cli_wallet" -s "ws://127.0.0.1:8091" -w $GOLOS_WALLET \
            -C "set_password $GOLOS_PASSWORD && unlock $GOLOS_PASSWORD && import_key $privatekey"
    fi

    array=("$@"); cmd=$1; shift
    for item in "$@"; do cmd="$cmd && $item"; done
    docker exec -ti $GOLOS_NAME "/usr/local/bin/cli_wallet" -s "ws://127.0.0.1:8091" -w $GOLOS_WALLET -C "$cmd"
}

goloschain_send_transit_operation() {
    echo "Send transit-operation by existing witness."

    local witness=${WITNESS:-$(get_config_value "witness" $GOLOS_CONFIG | sed 's/"//g')}
    if [ ! -z "$witness" ]; then
        send_cliwallet_commands "unlock $GOLOS_PASSWORD" "transit_to_cyberway $witness true" || true
        sleep 15
    fi
}

goloschain_first_run() {
    echo "Download last version of GolosChain image, prepare configuration for transit, and run it"

    docker pull $GOLOS_IMAGE

    mkdir -p $GOLOS_ETC
    mkdir -p $GOLOS_DATA

    # Stop and remove old container
    docker stop $GOLOS_NAME || true
    docker rm $GOLOS_NAME || true

    # Create temporaty container to copy configuration files from it
    docker create --name $GOLOS_NAME $GOLOS_IMAGE
    docker cp $GOLOS_NAME:$GOLOS_CONFIG $GOLOS_CONFIG
    docker cp $GOLOS_NAME:$GOLOS_SEEDNODES $GOLOS_SEEDNODES 2>/dev/null || true
    docker cp $GOLOS_NAME:$GOLOS_GENESIS $GOLOS_GENESIS 2>/dev/null || true
    docker rm $GOLOS_NAME

    # clear shared_memory file ...
    rm -f $GOLOS_STATE || true

    # clear block log
    rm -f $GOLOS_BLOCKLOG || true
    rm -f "$GOLOS_BLOCKLOG.index" || true

    # set transit configuration ...
    goloschain_set_transit_cfg
    [ "$DAPP_API_NODE" ] && goloschain_set_ee_genesis_cfg
    goloschain_create

    sleep 10

    witness=$(get_config_value "witness" $GOLOS_CONFIG)
    send_cliwallet_commands "unlock $GOLOS_PASSWORD" \
                            "create_account $witness golos \"\" \"1.000 GOLOS\" true" \
                            "create_account $witness golosio \"\" \"1.000 GOLOS\" true"
}

goloschain_existing_run() {
    echo "Change configuration for existing GolosChain container."
    echo "Normal case for existing Validator node."

    docker stop $GOLOS_NAME || true
    goloschain_set_transit_cfg
    docker start $GOLOS_NAME
}

goloschain_replaying_run() {
    echo "Change configuration for existing GolosChain blocklog."
    echo "Can be used for golos.io API node."

    docker pull $GOLOS_IMAGE
    docker stop $GOLOS_NAME || true
    docker rm $GOLOS_NAME || true

    # clear shared memory file ...
    rm -f $GOLOS_STATE || true

    goloschain_set_transit_cfg
    [ "$DAPP_API_NODE" ] && goloschain_set_ee_genesis_cfg
    goloschain_create
}

goloschain_create() {
    echo "Create docker container."
    docker run -d -p 4243:4243 -p 8090:8090 -p 8091:8091 \
        -v $GOLOS_ETC:$GOLOS_ETC \
        -v $GOLOS_DATA:$GOLOS_DATA \
        --name $GOLOS_NAME $GOLOS_IMAGE
}

goloschain_set_transit_cfg() {
    echo "Set transit configuration. "
    echo "EE-genesis is required only for golos.io API node. "

    rm -f $STATE_DUMP || true
    rm -rf $STATE_OPDUMP || true

    set_config_value 'serialize-delay-sec' $STATE_DELAY_SEC $GOLOS_CONFIG
    set_config_value 'serialize-state' $STATE_DUMP $GOLOS_CONFIG
}

goloschain_set_ee_genesis_cfg() {
    append_config_value 'plugin' 'operation_dump' $GOLOS_CONFIG
    append_config_value 'plugin' 'follow' $GOLOS_CONFIG
    set_config_value 'operation-dump-dir' $STATE_OPDUMP $GOLOS_CONFIG

    mkdir -p $STATE_OPDUMP
}


checkarg() {
    if [ "$2" ]; then
        return 0
    else
        echo "ERROR: $1 requires a non-empty argument" >&2
        exit 1
    fi
}

showhelp() {
    cat <<END
Use: transit.sh [OPTIONS] <action>
OPTIONS:
    -g,--goloschain-branch <value>    Use sub-branch GolosChain ($golos_branch)
    -c,--cyberway-branch <value>      CyberWay branch ($cyberway_branch)
    --goloschain-docker <value>       Name of docker for GolosChain node ($goloschain_name)
    -p,--cli-wallet-password <value>  Password for cli-wallet ($password)
    --genesis-delay <value>           Delay before start of state serializing. This delay is required to wait fixing Transit in LIB on the GolosChain network. ($delay_sec)
    -a,--dapp-api-node                Generate Event Genesis for Golos DApp ($api_node)
    --goloschain-ip <value>           IP of goloschain node for waiting of HF21

Possible actions:
    golos-first-run
    golos-existing-run
    golos-replaying-run
    hf21-wait
    transit-approve
    transit-local-wait
    transit-global-wait
    state-prestart-check
    cyberway-prestart-check
    cyberway-generate-genesis
    cyberway-download-genesis
    cyberway-first-run
    cyberway-clear-p2p-nodes
    cyberway-add-p2p-nodes
    username-to-account
END
}

goloschain_ip="127.0.0.1"
golos_branch="v0.21.0"
cyberway_branch="v2.1.0"
goloschain_name="golos-default"
password="qwerty"
delay_sec=300
api_node=''

while :; do
    case $1 in
        --goloschain-ip)
            checkarg $1 $2
            goloschain_ip=$2
            shift
            ;;
        -g|--goloschain-branch)
            checkarg $1 $2
            golos_branch=$2
            shift
            ;;
        -c|--cyberway-branch)
            checkarg $1 $2
            cyberway_branch=$2
            shift
            ;;
        --goloschain-docker)
            checkarg $1 $2
            goloschain_name=$2
            shift
            ;;
        -p|--cli-wallet-password)
            checkarg $1 $2
            password=$2
            shift
            ;;
        --genesis-delay)
            checkarg $1 $2
            delay_sec=$2
            shift
            ;;
        -a|--dapp-api-node)
            api_node=1
            ;;
        -h|--help)
            showhelp
            exit 0
            ;;
        -?*)
            echo "WARN: Unknown option (ignored): $1" >&2
            ;;
        *)
            break
    esac
    shift
done


if [ "$1" ]; then
    action=$1
    shift
else
    echo "ERROR: Missing required action" >&2
    exit 1
fi

[ $delay_sec -ge 15 ] || { echo "Delay for state serializing can't be less than 15 sec"; exit 1; }

GOLOS_NAME="$goloschain_name"
GOLOS_PASSWORD="$password"
GOLOS_IMAGE="goloschain/golos:$golos_branch"
GOLOS_ETC="/etc/golosd"
GOLOS_DATA="/var/lib/golosd"
GOLOS_CONFIG="$GOLOS_ETC/config.ini"
GOLOS_SEEDNODES="$GOLOS_ETC/seednodes"
GOLOS_GENESIS="$GOLOS_DATA/snapshot5392323.json"
GOLOS_WALLET="$GOLOS_DATA/witness-wallet.json"
GOLOS_STATE="$GOLOS_DATA/blockchain/shared_memory.bin"
GOLOS_BLOCKLOG="$GOLOS_DATA/blockchain/block_log"

STATE_DUMP="$GOLOS_DATA/cyberway/golos.dat"
STATE_OPDUMP="$GOLOS_DATA/operation_dump"
STATE_DELAY_SEC=$delay_sec

DAPP_IMAGE="cyberway/golos.contracts:$cyberway_branch"
DAPP_API_NODE=$api_node

CYBER_IMAGE="cyberway/cyberway:$cyberway_branch"
CYBER_ETC="/etc/cyberway"
CYBER_DATA="/var/lib/cyberway"
CYBER_CONFIG="$CYBER_ETC/config.ini"
CYBER_GENESIS="$CYBER_DATA/genesis-data"
CYBER_COMPOSE="$CYBER_DATA/docker-compose.yml"
CYBER_LAUNCH_URL='https://raw.githubusercontent.com/cyberway/cyberway.launch/master'

# perform actions that do not require `sudo`
user_action=1
case $action in
    hf21-wait)
        goloschain_wait_hf21
        ;;
    transit-local-wait)
        goloschain_wait_transit
        ;;
    transit-global-wait)
        launch_wait_transit
        ;;
    username-to-account)
        convert_username_to_account "$1"
        ;;
    *)
        user_action=''
esac

[ "$user_action" ] && exit 0

# perform actions that require `sudo`
[ $(whoami) == 'root' ] || { echo "Should be run under root"; exit 1; }

case $action in
    golos-first-run)
        goloschain_first_run
        ;;
    golos-existing-run)
        goloschain_existing_run
        ;;
    golos-replaying-run)
        goloschain_replaying_run
        ;;
    transit-approve)
        goloschain_send_transit_operation
        ;;
    state-prestart-check)
        state_prestart_check
        ;;
    cyberway-prestart-check)
        cyberway_prestart_check
        ;;
    cyberway-download-genesis)
        cyberway_download_genesis
        ;;
    cyberway-generate-genesis)
        cyberway_generate_genesis
        ;;
    cyberway-first-run)
        cyberway_first_run
        ;;
    cyberway-clear-p2p-nodes)
        cyberway_clear_p2p_nodes
        ;;
    cyberway-add-p2p-nodes)
        cyberway_add_p2p_nodes
        ;;
    *)
        echo "ERROR: Unknown action $action" >&2
        exit 1
esac

exit 0
