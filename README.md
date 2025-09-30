<table style="border-collapse: collapse; border: none;">
  <tr style="border-collapse: collapse; border: none;">
    <td style="border-collapse: collapse; border: none;">
      <a href="http://www.openairinterface.org/">
         <img src="https://gitlab.eurecom.fr/uploads/-/system/user/avatar/716/avatar.png?width=800" alt="" border=3 height=50 width=50>
         </img>
      </a>
    </td>
    <td style="border-collapse: collapse; border: none; vertical-align: center;">
      <b><font size = "5">Docker compose to deploy a 4G private cellular netwwork</font></b>
    </td>
  </tr>
</table>

# Author
**Luis Felipe Ariza Vesga** 
emails: lfarizav@gmail.com, lfarizav@unal.edu.co
# Project created from the following repositories
https://github.com/herlesupreeth/docker_open5gs and https://github.com/MAlexVR/docker_open5gs
# Descripción
This code allow to deploy a 4G private cellular networks with data, SMS, IPTV and VoLTE services

## Table of Contents

- [Descripción](#description)
- [Docker_open5gs software](#docker-software)
- [Tested Setup](#tested-setup)
- [Building docker images](#building)
  - [Clone repository and build base docker image of open5gs, kamailio, srsRAN_4G, srsRAN_Project, ueransim](#clonning-repository)
  - [Build docker images for additional components and deployed them](#building-repository)
- [Network and deployment configuration](#network-deployment-configuration)
  - [Host setup configuration](#host-setup-configuration)
---
[TOC](#table-of-contents)

### docker_open5gs software
Quite contrary to the name of the repository, this repository contains docker files to deploy an Over-The-Air (OTA) network using following projects:
- Core Network (4G/5G) - open5gs - https://github.com/open5gs/open5gs
- IMS (Only 4G supported i.e. VoLTE) - kamailio
- IMS HSS - https://github.com/nickvsnetworking/pyhss
- Osmocom HLR - https://github.com/osmocom/osmo-hlr
- Osmocom MSC - https://github.com/osmocom/osmo-msc
- srsRAN (4G/5G) - https://github.com/srsran/srsRAN
- UERANSIM (5G) - https://github.com/aligungr/UERANSIM

### Tested Setup

Docker host machine

- Ubuntu 22.04 / 24.04

Over-The-Air setups: 

- srsRAN (eNB/gNB) using Ettus USRP B200 mini-i

RF emulated setups:

 - open5GS (EPC) + srsRAN (eNB)

### Building docker images

* Mandatory requirements: latest docker version

#### Clone repository and build base docker image of open5gs, kamailio, srsRAN_4G, srsRAN_Project, ueransim

```
# Build docker images for open5gs EPC/5GC components
git clone https://github.com/lfarizav/docker_open5gs
cd docker_open5gs/base
docker build --no-cache --force-rm -t docker_open5gs .

# Build docker images for kamailio IMS components
cd ../ims_base
docker build --no-cache --force-rm -t docker_kamailio .

# Build docker images for srsRAN_4G eNB + srsUE (4G+5G)
cd ../srslte
docker build --no-cache --force-rm -t docker_srslte .
```

#### Build docker images for additional components and deployed them

```
cd ..
set -a
source .env
sudo ufw disable
sudo sysctl -w net.ipv4.ip_forward=1
sudo cpupower frequency-set -g performance

# For 4G deployment only
docker compose -f docker-compose.yaml -d
```

### Network and deployment configuration

#### Host setup configuration
Edit only the following parameters in **.env** as per your setup

```
DOCKER_HOST_IP --> This is the IP address of the host running your docker setup
SGWU_ADVERTISE_IP --> Change this to value of DOCKER_HOST_IP
UE_IPV4_INTERNET --> Change this to your desired (Not conflicted) UE network ip range for internet APN
UE_IPV4_IMS --> Change this to your desired (Not conflicted) UE network ip range for ims APN
```

### Network Deployment

###### 4G deployment

```
# 4G Core Network + IMS + SMS + OTA
docker compose -f docker-compose.yaml up
```
### Provisioning of SIM information
```
[Manually](https://github.com/MAlexVR/docker_open5gs)
```
#### Provisioning of IMSI and MSISDN with OsmoHLR as follows:

1. First, login to the osmohlr container

```
docker exec -it osmohlr /bin/bash
```

2. Then, telnet to localhost

```
$ telnet localhost 4258

OsmoHLR> enable
OsmoHLR#
```

3. Finally, register the subscriber information as in following example:

```
OsmoHLR# subscriber imsi 001010123456790 create
OsmoHLR# subscriber imsi 001010123456790 update msisdn 9076543210
OsmoHLR# show subcribers all
```

**Replace IMSI and MSISDN as per your programmed SIM**


### Provisioning of SIM information in pyHSS is as follows:

```
https://github.com/MAlexVR/docker_open5gs
```
# docker_open5gs
