#!/bin/bash
docker stop $(docker ps -a -q) 
docker compose -f 4g-volte-deploy.yaml up -d
docker-compose -f wowza.yaml up -d
docker-compose -f srsenb.yaml up -d
