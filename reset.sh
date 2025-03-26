#!/bin/bash
docker stop $(docker ps -a -q) 
docker rm $(docker ps -a -q)
cd $HOME/docker_open5gs
set -a
source .env
sudo ufw disable
sudo sysctl -w net.ipv4.ip_forward=1
sudo cpupower frequency-set -g performance
docker compose -f wowza.yaml up -d
docker compose -f srsenb.yaml up -d
docker compose -f 4g-volte-deploy.yaml up -d
