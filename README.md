<img width="400" src="./images/logo.jpg" />

# Mainnet

The current CyberWay version: [v2.0.2](https://github.com/cyberway/cyberway/releases/tag/v2.0.2)

# Running node

Clone this repository and run `./start_light.sh`

# Upgrade from v2.0.1 to v2.0.2

1. Download the docker image `cyberway/cyberway:v2.0.2`:
```
sudo docker pull cyberway/cyberway:v2.0.2
```

2. Download the last version of `docker-compose.yml` from the [GitHub](https://raw.githubusercontent.com/cyberway/cyberway.launch/master/docker-compose.yml)

```
sudo curl https://raw.githubusercontent.com/cyberway/cyberway.launch/master/docker-compose.yml --output /var/lib/cyberway/docker-compose.yml
```

3. Restart the nodeos container:
```
cd /var/lib/cyberway
sudo docker-compose up -t 120 -d
```

# Migration of the Golos blockchain

To start the transit you have to clone the contents of the repository and run `./start_check_state.sh`

## Preconditions

The shell script is configured to work with the following files:
- Path to the state and block-log: `/va/lib/golosd`
- Path to the configuration file: `/etc/golosd/config.ini`

If your configuration does not match this one, you should correct the variable values in the `transit.sh` file.

## Transit approval

The shell script `transit.sh` contains command `transit-approve`, which is called from the `start_check_state.sh`. To send operation `transit_to_cyberway` the script should sign it with the witness key taken from the file `/etc/golosd/config.ini`. The problem is that the signature of the witness key may not match the signature of the active account key. 

Please check this out. If so, then in this case you need to comment out the line containing `transit-approve` and send a transaction with the `transit_to_cyberway` operation manually. You can do it by using `cli_wallet`.
