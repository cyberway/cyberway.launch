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
