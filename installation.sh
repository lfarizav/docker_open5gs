#!/bin/bash
# Script developed by Luis Felipe Ariza Vesga
# lfarizav@gmail.com, lfarizav@unal.edu.co
set -e
function get_ip_address() {
    # Get the IP address of the first active network interface
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    # Check if the IP_ADDRESS is empty
    if [[ -z "$IP_ADDRESS" ]]; then
        echo "No IP address found."
        return 1
    else
        echo "$IP_ADDRESS"
        return 0
    fi
}

cecho()  {
    # Color-echo
    # arg1 = message
    # arg2 = color
    local default_msg="No Message."
    message=${1:-$default_msg}
    color=${2:-$green}
    echo -e "$color$message$reset_color"
    return
}

echo_info()    { cecho "$*" $blue         ;}
function install_dependencies() {
    # Update package list and install dependencies
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl

    # Set up Docker GPG key and repository
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository to sources list
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package list and install Docker components
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git

    # Add user to Docker group
    sudo groupadd docker || true  # Avoid error if the group already exists
    sudo usermod -aG docker "$USER"

    # Display Docker versions
    docker --version
    docker compose --version
    sudo apt install net-tools plocate traceroute git python3 python3-pip wireshark xterm -y
    sudo usermod -aG wireshark $(whoami)
    echo "Docker installation complete. Please log out and log back in to apply group changes for Docker access without sudo."
}
function build_images() {
    # Exit on any error
    set -e

    # Define repository URL and image names
    REPO_URL="https://github.com/lfarizav/docker_open5gs.git"
    BASE_IMAGE="docker_open5gs"
    IMS_IMAGE="docker_kamailio"
    SRSLTE_IMAGE="docker_srslte"
    SRSRAN_IMAGE="docker_srsran"

    # Clone the repository if not already cloned
    if [ ! -d "$HOME/docker_open5gs" ]; then
        echo "Cloning Open5GS repository..."
        git clone "$REPO_URL" "$HOME/docker_open5gs"
    fi

    # Build Docker images
    echo "Building Open5GS EPC/5GC component image..."
    cd "$HOME/docker_open5gs/base"
    docker build --no-cache --force-rm -t "$BASE_IMAGE" .

    echo "Building Kamailio IMS component image..."
    cd "$HOME/docker_open5gs/ims_base"
    docker build --no-cache --force-rm -t "$IMS_IMAGE" .

    echo "Building srsRAN_4G eNB + srsUE image..."
    cd "$HOME/docker_open5gs/srslte"
    docker build --no-cache --force-rm -t "$SRSLTE_IMAGE" .

    # Build docker images for srsRAN_Project gNB
    cd "$HOME/docker_open5gs/srsran"
    docker build --no-cache --force-rm -t "$SRSRAN_IMAGE" .

    # Build and deploy containers
    echo "Building and deploying containers with docker compose..."
    cd "$HOME/docker_open5gs"
    docker compose -f wowza.yaml build --no-cache

    echo "All Docker images built and containers deployed successfully."
}
function uhd_installation_host() {
    # Exit on any error
    set -e

    echo "Installing UHD dependencies and software..."
    sudo apt-get update -y
    sudo apt-get install -y libuhd-dev uhd-host
    sudo sudo /usr/lib/uhd/utils/uhd_images_downloader.py
    echo "Checking if UHD is correctly installed and functioning..."
    if sudo uhd_find_devices; then
        echo "UHD installation successful and device check passed."
    else
        echo "UHD installation completed, but no UHD devices were found. Please verify connections or installation."
    fi
}
function deploying() {
    # Exit on any error
    set -e

    # Define the project directory
    PROJECT_DIR="$HOME/docker_open5gs"

    # Navigate to project directory and check it exists
    if [ -d "$PROJECT_DIR" ]; then
        cd "$PROJECT_DIR"
    else
        echo "Directory $PROJECT_DIR does not exist. Please ensure the repository is cloned."
        exit 1
    fi

    # Load environment variables
    echo "Loading environment variables..."
    set -a
    source .env
    set +a
    sudo cpupower frequency-set -g performance
    # Configure host settings
    echo "Configuring host settings..."
    sudo ufw disable
    sudo sysctl -w net.ipv4.ip_forward=1

    # Deploy containers
    echo "Deploying 4G Core Network + IMS + SMS over SGs with Grafana..."
    sudo docker compose -f 4g-volte-deploy.yaml up -d

    echo "Deploying srsLTE eNB..."
    sudo docker compose -f srsenb.yaml up -d

    echo "Deploying Wowza Streaming Engine..."
    sudo docker compose -f wowza.yaml up -d

    echo "Deployment complete. All containers are running in detached mode."
}
function hss_configuration() {
    # Define the project directory
    PROJECT_DIR="$HOME/docker_open5gs"

    # Navigate to project directory and check if it exists
    if [ -d "$PROJECT_DIR" ]; then
        cd "$PROJECT_DIR"
    else
        echo "Directory $PROJECT_DIR does not exist. Please ensure the repository is cloned."
        exit 1
    fi

    # Copy the open5gs-dbctl file from the project directory to the HSS container
    docker cp "$PROJECT_DIR/open5gs-dbctl" hss:/open5gs/misc/db/open5gs-dbctl 
    docker exec hss chmod +x /open5gs/misc/db/open5gs-dbctl

    # Array of subscriber details (IMSI, MSISDN, keys)
    declare -a subscribers=(
        "001010000010001 10001 5BAD8598D1F631E3ED76F9333B8AA26F BA5205DDC6FCA1DF6B83A1CC69859514"
        "001010000010002 10002 DA4EDB6503743D404DA2F91A4446C26F 1CFA68FDE88DCA322C1BF33D0F2709A0"
        "001010000010003 10003 77D10F5D09292E898DA97F36CBA22275 15F2BE54160B450B79BD425EC10B4C81"
        "001010000010004 10004 F47B5443F09760E05BDEF9D10A86D6C3 235328F1832BC91BBD7A0CBD271E4DC9"
        "001010000010005 10005 7E4398F2720DB23C49D711C19E2C4738 BF8A9A0FE50B68215B8462791F2B6254"
        "001010000010006 10006 674E74E187D604A923E2614184CF6912 A97AEDAE1876B03B321278978AAC3AD8"
        "001010000010007 10007 FABB585E5D82F89AB66728D945603E71 92639359563FF33FFFDE8D75EAD9596A"
        "001010000010008 10008 D16E183E912C7F2CF4832207B3F58D3F 75AE45E2B4BB8664B523177C444A14A0"
        "001010000010009 10009 37E439EA2BD7F361F850C5F58CA20DD7 A75DC1873E450721295B9B04D2A7AE6A"
        "001010000010010 10010 60708BDDF6326C6BFA8037B1102142C1 4BA3082D54CC63289EF2CCE378370629"
        "001010000010011 10011 21B711ECDD88FB0ACEAD1A5065A5ED5F 5F521CF371827170E905828174F70307"
        "001010000010012 10012 A9F1353840A2537D0184FE63F69BF173 8846E90976FFFD5E00EB8E3AFA2A6957"
        "001010000010013 10013 9FAC18853B562FAF9F209220CD6F0C49 1F76826FA18276917942D5E7F7FDD04B"
        "001010000010014 10014 23902E60F93A036422402759FFF0275E 9F604BC4276A8718072D55B70B209C63"
        "001010000010015 10015 C37442D65F7DFC441F78086FED28E3EE 571A8CF0573B4865D208D68B3CC7125C"
        "001010000010016 10016 62B54E105F224799EA90E1029F8D6C5F 6791D6A30E9958EE4ABB616D1A7B3201"
        "001010000010017 10017 D9555A8C944DB5F239E4CB72A1877561 551F2B078F6D5DFE773332C3B233CACE"
        "001010000010018 10018 A6AC83B95BFE6858D02B7D8BB5148575 348845B8A25055432C81D4BDF762879D"
        "001010000010019 10019 4DFD1ACBE2BDCA7843A8CA052A2F33A1 D2F17ECD4855FCB7D29CCB20C216EA70"
    )

    # Loop through the subscriber details and execute the add command
    for subscriber in "${subscribers[@]}"; do
        # Split the subscriber details into variables
        read -r imsi msisdn key1 key2 <<< "$subscriber"
        # Execute the command to add the subscriber using open5gs-dbctl
        sudo docker exec -it hss misc/db/open5gs-dbctl add "$imsi" "$msisdn" "$key1" "$key2" 8000
    done
}

function osmohlr_configuration() {
    # Execute commands within the 'osmohlr' Docker container to configure OpenHLR over Telnet
    docker exec -i osmohlr telnet localhost 4258 << EOF
    # Enter privileged mode in Telnet
    enable
    
    # Display all current subscribers (for verification purposes)
    show subscribers all

    # Create and update subscribers with specific IMSIs and MSISDNs
    # Adding each subscriber and setting their respective MSISDNs
    subscriber imsi 001010000010001 create
    subscriber imsi 001010000010001 update msisdn 10001
    
    subscriber imsi 001010000010002 create
    subscriber imsi 001010000010002 update msisdn 10002
    
    subscriber imsi 001010000010003 create
    subscriber imsi 001010000010003 update msisdn 10003
    
    subscriber imsi 001010000010004 create
    subscriber imsi 001010000010004 update msisdn 10004
    
    subscriber imsi 001010000010005 create
    subscriber imsi 001010000010005 update msisdn 10005
    
    subscriber imsi 001010000010006 create
    subscriber imsi 001010000010006 update msisdn 10006
    
    subscriber imsi 001010000010007 create
    subscriber imsi 001010000010007 update msisdn 10007
    
    subscriber imsi 001010000010008 create
    subscriber imsi 001010000010008 update msisdn 10008
    
    subscriber imsi 001010000010009 create
    subscriber imsi 001010000010009 update msisdn 10009
    
    subscriber imsi 001010000010010 create
    subscriber imsi 001010000010010 update msisdn 10010
    
    subscriber imsi 001010000010011 create
    subscriber imsi 001010000010011 update msisdn 10011
    
    subscriber imsi 001010000010012 create
    subscriber imsi 001010000010012 update msisdn 10012
    
    subscriber imsi 001010000010013 create
    subscriber imsi 001010000010013 update msisdn 10013
    
    subscriber imsi 001010000010014 create
    subscriber imsi 001010000010014 update msisdn 10014
    
    subscriber imsi 001010000010015 create
    subscriber imsi 001010000010015 update msisdn 10015
    
    subscriber imsi 001010000010016 create
    subscriber imsi 001010000010016 update msisdn 10016
    
    subscriber imsi 001010000010017 create
    subscriber imsi 001010000010017 update msisdn 10017
    
    subscriber imsi 001010000010018 create
    subscriber imsi 001010000010018 update msisdn 10018
    
    subscriber imsi 001010000010019 create
    subscriber imsi 001010000010019 update msisdn 10019
EOF
}
function pyhss_configuration() {
    # Check if the correct number of arguments are provided
    if [ "$#" -ne 2 ]; then
        echo "Usage: pyhss_configuration <IP_ADDRESS> <PORT>"
        return 1
    fi

    # Define the base URL for the API using the provided IP and port
    local IP_ADDRESS="$1"
    local PORT="$2"
    local BASE_URL="http://$IP_ADDRESS:$PORT"
    local apn_name=""
    local apn_id=1
    # Load and configure Access Point Names (APNs)
    apn_name="internet"
    apn_id=1
    sudo docker exec -it pyhss curl -X 'PUT' \
            "$BASE_URL/apn/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"apn\": \"$apn_name\",
                \"pgw_address\": \"string\",
                \"charging_characteristics\": \"stri\",
                \"apn_ambr_ul\": 0,
                \"arp_priority\": 0,
                \"arp_preemption_capability\": true,
                \"charging_rule_list\": \"string\",
                \"ip_version\": 0,
                \"apn_id\": $apn_id,
                \"sgw_address\": \"string\",
                \"apn_ambr_dl\": 0,
                \"qci\": 0,
                \"arp_preemption_vulnerability\": true,
                \"last_modified\": \"2024-07-11T15:18:10Z\"
            }"
    apn_name="ims"
    apn_id=2
    sudo docker exec -it pyhss curl -X 'PUT' \
            "$BASE_URL/apn/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"apn\": \"$apn_name\",
                \"pgw_address\": \"string\",
                \"charging_characteristics\": \"stri\",
                \"apn_ambr_ul\": 0,
                \"arp_priority\": 0,
                \"arp_preemption_capability\": true,
                \"charging_rule_list\": \"string\",
                \"ip_version\": 0,
                \"apn_id\": $apn_id,
                \"sgw_address\": \"string\",
                \"apn_ambr_dl\": 0,
                \"qci\": 0,
                \"arp_preemption_vulnerability\": true,
                \"last_modified\": \"2024-07-11T15:18:10Z\"
            }"
    # Load and configure Authentication Centers (AUCs)

	local ki=""
	local opc=""
	local icci""
	local imsi=""
	local auc_id=1
        ki="5BAD8598D1F631E3ED76F9333B8AA26F"
        opc="BA5205DDC6FCA1DF6B83A1CC69859514"
        iccid="8988211000000543515"
        imsi="001010000010001" 
        auc_id=1   
        curl -X 'PUT' \
            "$BASE_URL/auc/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"auc_id\": $auc_id,
                \"ki\": \"$ki\",
                \"opc\": \"$opc\",
                \"amf\": \"8000\",
                \"sqn\": 0,
                \"iccid\": \"$iccid\",
                \"imsi\": \"$imsi\",
                \"batch_name\": \"string\",
                \"sim_vendor\": \"string\",
                \"esim\": true,
                \"lpa\": \"string\",
                \"pin1\": \"string\",
                \"pin2\": \"string\",
                \"puk1\": \"string\",
                \"puk2\": \"string\",
                \"kid\": \"string\",
                \"psk\": \"string\",
                \"des\": \"string\",
                \"adm1\": \"string\",
                \"misc1\": \"string\",
                \"misc2\": \"string\",
                \"misc3\": \"string\",
                \"misc4\": \"string\"
            }"
	auc_id=2
        ki="DA4EDB6503743D404DA2F91A4446C26F"
        opc="1CFA68FDE88DCA322C1BF33D0F2709A0"
        iccid="8988211000000543523"
        imsi="001010000010002"
        curl -X 'PUT' \
            "$BASE_URL/auc/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"auc_id\": $auc_id,
                \"ki\": \"$ki\",
                \"opc\": \"$opc\",
                \"amf\": \"8000\",
                \"sqn\": 0,
                \"iccid\": \"$iccid\",
                \"imsi\": \"$imsi\",
                \"batch_name\": \"string\",
                \"sim_vendor\": \"string\",
                \"esim\": true,
                \"lpa\": \"string\",
                \"pin1\": \"string\",
                \"pin2\": \"string\",
                \"puk1\": \"string\",
                \"puk2\": \"string\",
                \"kid\": \"string\",
                \"psk\": \"string\",
                \"des\": \"string\",
                \"adm1\": \"string\",
                \"misc1\": \"string\",
                \"misc2\": \"string\",
                \"misc3\": \"string\",
                \"misc4\": \"string\"
            }"
        auc_id=3
        ki="77D10F5D09292E898DA97F36CBA22275"
        opc="15F2BE54160B450B79BD425EC10B4C81"
        iccid="8988211000000543531"
        imsi="001010000010003"
        curl -X 'PUT' \
            "$BASE_URL/auc/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"auc_id\": $auc_id,
                \"ki\": \"$ki\",
                \"opc\": \"$opc\",
                \"amf\": \"8000\",
                \"sqn\": 0,
                \"iccid\": \"$iccid\",
                \"imsi\": \"$imsi\",
                \"batch_name\": \"string\",
                \"sim_vendor\": \"string\",
                \"esim\": true,
                \"lpa\": \"string\",
                \"pin1\": \"string\",
                \"pin2\": \"string\",
                \"puk1\": \"string\",
                \"puk2\": \"string\",
                \"kid\": \"string\",
                \"psk\": \"string\",
                \"des\": \"string\",
                \"adm1\": \"string\",
                \"misc1\": \"string\",
                \"misc2\": \"string\",
                \"misc3\": \"string\",
                \"misc4\": \"string\"
            }"
        auc_id=4
        ki="F47B5443F09760E05BDEF9D10A86D6C3"
        opc="235328F1832BC91BBD7A0CBD271E4DC9"
        iccid="8988211000000543549"
        imsi="001010000010004"
        curl -X 'PUT' \
            "$BASE_URL/auc/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"auc_id\": $auc_id,
                \"ki\": \"$ki\",
                \"opc\": \"$opc\",
                \"amf\": \"8000\",
                \"sqn\": 0,
                \"iccid\": \"$iccid\",
                \"imsi\": \"$imsi\",
                \"batch_name\": \"string\",
                \"sim_vendor\": \"string\",
                \"esim\": true,
                \"lpa\": \"string\",
                \"pin1\": \"string\",
                \"pin2\": \"string\",
                \"puk1\": \"string\",
                \"puk2\": \"string\",
                \"kid\": \"string\",
                \"psk\": \"string\",
                \"des\": \"string\",
                \"adm1\": \"string\",
                \"misc1\": \"string\",
                \"misc2\": \"string\",
                \"misc3\": \"string\",
                \"misc4\": \"string\"
            }"
        auc_id=5
        ki="7E4398F2720DB23C49D711C19E2C4738"
        opc="BF8A9A0FE50B68215B8462791F2B6254"
        iccid="8988211000000543556"
        imsi="001010000010005"
        curl -X 'PUT' \
            "$BASE_URL/auc/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"auc_id\": $auc_id,
                \"ki\": \"$ki\",
                \"opc\": \"$opc\",
                \"amf\": \"8000\",
                \"sqn\": 0,
                \"iccid\": \"$iccid\",
                \"imsi\": \"$imsi\",
                \"batch_name\": \"string\",
                \"sim_vendor\": \"string\",
                \"esim\": true,
                \"lpa\": \"string\",
                \"pin1\": \"string\",
                \"pin2\": \"string\",
                \"puk1\": \"string\",
                \"puk2\": \"string\",
                \"kid\": \"string\",
                \"psk\": \"string\",
                \"des\": \"string\",
                \"adm1\": \"string\",
                \"misc1\": \"string\",
                \"misc2\": \"string\",
                \"misc3\": \"string\",
                \"misc4\": \"string\"
            }"
        auc_id=6
        ki="674E74E187D604A923E2614184CF6912"
        opc="A97AEDAE1876B03B321278978AAC3AD8"
        iccid="8988211000000543564"
        imsi="001010000010006"
        curl -X 'PUT' \
            "$BASE_URL/auc/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"auc_id\": $auc_id,
                \"ki\": \"$ki\",
                \"opc\": \"$opc\",
                \"amf\": \"8000\",
                \"sqn\": 0,
                \"iccid\": \"$iccid\",
                \"imsi\": \"$imsi\",
                \"batch_name\": \"string\",
                \"sim_vendor\": \"string\",
                \"esim\": true,
                \"lpa\": \"string\",
                \"pin1\": \"string\",
                \"pin2\": \"string\",
                \"puk1\": \"string\",
                \"puk2\": \"string\",
                \"kid\": \"string\",
                \"psk\": \"string\",
                \"des\": \"string\",
                \"adm1\": \"string\",
                \"misc1\": \"string\",
                \"misc2\": \"string\",
                \"misc3\": \"string\",
                \"misc4\": \"string\"
            }"
        auc_id=7
        ki="FABB585E5D82F89AB66728D945603E71"
        opc="92639359563FF33FFFDE8D75EAD9596A"
        iccid="8988211000000543572"
        imsi="001010000010007"
        curl -X 'PUT' \
            "$BASE_URL/auc/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"auc_id\": $auc_id,
                \"ki\": \"$ki\",
                \"opc\": \"$opc\",
                \"amf\": \"8000\",
                \"sqn\": 0,
                \"iccid\": \"$iccid\",
                \"imsi\": \"$imsi\",
                \"batch_name\": \"string\",
                \"sim_vendor\": \"string\",
                \"esim\": true,
                \"lpa\": \"string\",
                \"pin1\": \"string\",
                \"pin2\": \"string\",
                \"puk1\": \"string\",
                \"puk2\": \"string\",
                \"kid\": \"string\",
                \"psk\": \"string\",
                \"des\": \"string\",
                \"adm1\": \"string\",
                \"misc1\": \"string\",
                \"misc2\": \"string\",
                \"misc3\": \"string\",
                \"misc4\": \"string\"
            }"
        auc_id=8
        ki="D16E183E912C7F2CF4832207B3F58D3F"
        opc="75AE45E2B4BB8664B523177C444A14A0"
        iccid="8988211000000543580"
        imsi="001010000010008"
        curl -X 'PUT' \
            "$BASE_URL/auc/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"auc_id\": $auc_id,
                \"ki\": \"$ki\",
                \"opc\": \"$opc\",
                \"amf\": \"8000\",
                \"sqn\": 0,
                \"iccid\": \"$iccid\",
                \"imsi\": \"$imsi\",
                \"batch_name\": \"string\",
                \"sim_vendor\": \"string\",
                \"esim\": true,
                \"lpa\": \"string\",
                \"pin1\": \"string\",
                \"pin2\": \"string\",
                \"puk1\": \"string\",
                \"puk2\": \"string\",
                \"kid\": \"string\",
                \"psk\": \"string\",
                \"des\": \"string\",
                \"adm1\": \"string\",
                \"misc1\": \"string\",
                \"misc2\": \"string\",
                \"misc3\": \"string\",
                \"misc4\": \"string\"
            }"
        auc_id=9
        ki="37E439EA2BD7F361F850C5F58CA20DD7"
        opc="A75DC1873E450721295B9B04D2A7AE6A"
        iccid="8988211000000543598"
        imsi="001010000010009"
        curl -X 'PUT' \
            "$BASE_URL/auc/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"auc_id\": $auc_id,
                \"ki\": \"$ki\",
                \"opc\": \"$opc\",
                \"amf\": \"8000\",
                \"sqn\": 0,
                \"iccid\": \"$iccid\",
                \"imsi\": \"$imsi\",
                \"batch_name\": \"string\",
                \"sim_vendor\": \"string\",
                \"esim\": true,
                \"lpa\": \"string\",
                \"pin1\": \"string\",
                \"pin2\": \"string\",
                \"puk1\": \"string\",
                \"puk2\": \"string\",
                \"kid\": \"string\",
                \"psk\": \"string\",
                \"des\": \"string\",
                \"adm1\": \"string\",
                \"misc1\": \"string\",
                \"misc2\": \"string\",
                \"misc3\": \"string\",
                \"misc4\": \"string\"
            }"
        auc_id=10
        ki="C3FC282C9B6A54808943FC459D5E1AA7"
        opc="5F7C927A46B140E5411E90AEDC8E397B"
        iccid="8949440000001144508"
        imsi="001010000010010"
        curl -X 'PUT' \
            "$BASE_URL/auc/" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{
                \"auc_id\": $auc_id,
                \"ki\": \"$ki\",
                \"opc\": \"$opc\",
                \"amf\": \"8000\",
                \"sqn\": 0,
                \"iccid\": \"$iccid\",
                \"imsi\": \"$imsi\",
                \"batch_name\": \"string\",
                \"sim_vendor\": \"string\",
                \"esim\": true,
                \"lpa\": \"string\",
                \"pin1\": \"string\",
                \"pin2\": \"string\",
                \"puk1\": \"string\",
                \"puk2\": \"string\",
                \"kid\": \"string\",
                \"psk\": \"string\",
                \"des\": \"string\",
                \"adm1\": \"string\",
                \"misc1\": \"string\",
                \"misc2\": \"string\",
                \"misc3\": \"string\",
                \"misc4\": \"string\"
            }"
    # Load and configure subscribers
    curl -X 'PUT' \
        "$BASE_URL/subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "imsi": "001010000010001", 
            "nam": 0,   
            "serving_mme_peer": null,
            "enabled": true,
            "roaming_enabled": true,
            "last_modified": "2024-09-22T01:16:40Z",
            "auc_id": 1,
            "roaming_rule_list": null,
            "default_apn": 1,
            "subscribed_rau_tau_timer": 300,
            "apn_list": "1,2",
            "serving_mme": null,
            "msisdn": "10001",
            "serving_mme_timestamp": null,
            "subscriber_id": 1,
            "ue_ambr_dl": 0,
            "serving_mme_realm": null,
            "ue_ambr_ul": 0
        }'
    curl -X 'PUT' \
        "$BASE_URL/subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "imsi": "001010000010002", 
            "nam": 0,   
            "serving_mme_peer": null,
            "enabled": true,
            "roaming_enabled": true,
            "last_modified": "2024-09-22T01:16:40Z",
            "auc_id": 2,
            "roaming_rule_list": null,
            "default_apn": 1,
            "subscribed_rau_tau_timer": 300,
            "apn_list": "1,2",
            "serving_mme": null,
            "msisdn": "10002",
            "serving_mme_timestamp": null,
            "subscriber_id": 2,
            "ue_ambr_dl": 0,
            "serving_mme_realm": null,
            "ue_ambr_ul": 0
        }'
        curl -X 'PUT' \
        "$BASE_URL/subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "imsi": "001010000010003", 
            "nam": 0,   
            "serving_mme_peer": null,
            "enabled": true,
            "roaming_enabled": true,
            "last_modified": "2024-09-22T01:16:40Z",
            "auc_id": 3,
            "roaming_rule_list": null,
            "default_apn": 1,
            "subscribed_rau_tau_timer": 300,
            "apn_list": "1,2",
            "serving_mme": null,
            "msisdn": "10003",
            "serving_mme_timestamp": null,
            "subscriber_id": 3,
            "ue_ambr_dl": 0,
            "serving_mme_realm": null,
            "ue_ambr_ul": 0
        }'    
            curl -X 'PUT' \
        "$BASE_URL/subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "imsi": "001010000010004", 
            "nam": 0,   
            "serving_mme_peer": null,
            "enabled": true,
            "roaming_enabled": true,
            "last_modified": "2024-09-22T01:16:40Z",
            "auc_id": 4,
            "roaming_rule_list": null,
            "default_apn": 1,
            "subscribed_rau_tau_timer": 300,
            "apn_list": "1,2",
            "serving_mme": null,
            "msisdn": "10004",
            "serving_mme_timestamp": null,
            "subscriber_id": 4,
            "ue_ambr_dl": 0,
            "serving_mme_realm": null,
            "ue_ambr_ul": 0
        }'
            curl -X 'PUT' \
        "$BASE_URL/subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "imsi": "001010000010005", 
            "nam": 0,   
            "serving_mme_peer": null,
            "enabled": true,
            "roaming_enabled": true,
            "last_modified": "2024-09-22T01:16:40Z",
            "auc_id": 5,
            "roaming_rule_list": null,
            "default_apn": 1,
            "subscribed_rau_tau_timer": 300,
            "apn_list": "1,2",
            "serving_mme": null,
            "msisdn": "10005",
            "serving_mme_timestamp": null,
            "subscriber_id": 5,
            "ue_ambr_dl": 0,
            "serving_mme_realm": null,
            "ue_ambr_ul": 0
        }'
            curl -X 'PUT' \
        "$BASE_URL/subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "imsi": "001010000010006", 
            "nam": 0,   
            "serving_mme_peer": null,
            "enabled": true,
            "roaming_enabled": true,
            "last_modified": "2024-09-22T01:16:40Z",
            "auc_id": 6,
            "roaming_rule_list": null,
            "default_apn": 1,
            "subscribed_rau_tau_timer": 300,
            "apn_list": "1,2",
            "serving_mme": null,
            "msisdn": "10006",
            "serving_mme_timestamp": null,
            "subscriber_id": 6,
            "ue_ambr_dl": 0,
            "serving_mme_realm": null,
            "ue_ambr_ul": 0
        }'
            curl -X 'PUT' \
        "$BASE_URL/subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "imsi": "001010000010007", 
            "nam": 0,   
            "serving_mme_peer": null,
            "enabled": true,
            "roaming_enabled": true,
            "last_modified": "2024-09-22T01:16:40Z",
            "auc_id": 7,
            "roaming_rule_list": null,
            "default_apn": 1,
            "subscribed_rau_tau_timer": 300,
            "apn_list": "1,2",
            "serving_mme": null,
            "msisdn": "10007",
            "serving_mme_timestamp": null,
            "subscriber_id": 7,
            "ue_ambr_dl": 0,
            "serving_mme_realm": null,
            "ue_ambr_ul": 0
        }'
            curl -X 'PUT' \
        "$BASE_URL/subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "imsi": "001010000010008", 
            "nam": 0,   
            "serving_mme_peer": null,
            "enabled": true,
            "roaming_enabled": true,
            "last_modified": "2024-09-22T01:16:40Z",
            "auc_id": 8,
            "roaming_rule_list": null,
            "default_apn": 1,
            "subscribed_rau_tau_timer": 300,
            "apn_list": "1,2",
            "serving_mme": null,
            "msisdn": "10008",
            "serving_mme_timestamp": null,
            "subscriber_id": 8,
            "ue_ambr_dl": 0,
            "serving_mme_realm": null,
            "ue_ambr_ul": 0
        }'
            curl -X 'PUT' \
        "$BASE_URL/subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "imsi": "001010000010009", 
            "nam": 0,   
            "serving_mme_peer": null,
            "enabled": true,
            "roaming_enabled": true,
            "last_modified": "2024-09-22T01:16:40Z",
            "auc_id": 9,
            "roaming_rule_list": null,
            "default_apn": 1,
            "subscribed_rau_tau_timer": 300,
            "apn_list": "1,2",
            "serving_mme": null,
            "msisdn": "10009",
            "serving_mme_timestamp": null,
            "subscriber_id": 9,
            "ue_ambr_dl": 0,
            "serving_mme_realm": null,
            "ue_ambr_ul": 0
        }'
            curl -X 'PUT' \
        "$BASE_URL/subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "imsi": "001010000010010", 
            "nam": 0,   
            "serving_mme_peer": null,
            "enabled": true,
            "roaming_enabled": true,
            "last_modified": "2024-09-22T01:16:40Z",
            "auc_id": 10,
            "roaming_rule_list": null,
            "default_apn": 1,
            "subscribed_rau_tau_timer": 300,
            "apn_list": "1,2",
            "serving_mme": null,
            "msisdn": "10010",
            "serving_mme_timestamp": null,
            "subscriber_id": 10,
            "ue_ambr_dl": 0,
            "serving_mme_realm": null,
            "ue_ambr_ul": 0
        }'
    # Load and configure IMS subscribers
    curl -X 'PUT' \
        "$BASE_URL/ims_subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "ifc_path": "default_ifc.xml",   
            "sh_profile": "string",
            "pcscf": null, 
            "scscf": "sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060",
            "pcscf_realm": null,
            "scscf_timestamp": "2024-10-02 16:46:14",
            "pcscf_active_session": null,
            "scscf_realm": "ims.mnc001.mcc001.3gppnetwork.org",
            "ims_subscriber_id": 1,
            "pcscf_timestamp": null,
            "scscf_peer": "scscf.ims.mnc001.mcc001.3gppnetwork.org;hss.ims.mnc001.mcc001.3gppnetwork.org",
            "msisdn": "10001",
            "pcscf_peer": null,
            "sh_template_path": null,
            "msisdn_list": "[10001]",
            "xcap_profile": null,
            "last_modified": "2024-10-22T01:19:26Z",
            "imsi": "001010000010001"
        }'
            curl -X 'PUT' \
        "$BASE_URL/ims_subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "ifc_path": "default_ifc.xml",   
            "sh_profile": "string",
            "pcscf": null, 
            "scscf": "sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060",
            "pcscf_realm": null,
            "scscf_timestamp": "2024-10-02 16:46:14",
            "pcscf_active_session": null,
            "scscf_realm": "ims.mnc001.mcc001.3gppnetwork.org",
            "ims_subscriber_id": 2,
            "pcscf_timestamp": null,
            "scscf_peer": "scscf.ims.mnc001.mcc001.3gppnetwork.org;hss.ims.mnc001.mcc001.3gppnetwork.org",
            "msisdn": "10002",
            "pcscf_peer": null,
            "sh_template_path": null,
            "msisdn_list": "[10002]",
            "xcap_profile": null,
            "last_modified": "2024-10-22T01:19:26Z",
            "imsi": "001010000010002"
        }'
            curl -X 'PUT' \
        "$BASE_URL/ims_subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "ifc_path": "default_ifc.xml",   
            "sh_profile": "string",
            "pcscf": null, 
            "scscf": "sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060",
            "pcscf_realm": null,
            "scscf_timestamp": "2024-10-02 16:46:14",
            "pcscf_active_session": null,
            "scscf_realm": "ims.mnc001.mcc001.3gppnetwork.org",
            "ims_subscriber_id": 3,
            "pcscf_timestamp": null,
            "scscf_peer": "scscf.ims.mnc001.mcc001.3gppnetwork.org;hss.ims.mnc001.mcc001.3gppnetwork.org",
            "msisdn": "10003",
            "pcscf_peer": null,
            "sh_template_path": null,
            "msisdn_list": "[10003]",
            "xcap_profile": null,
            "last_modified": "2024-10-22T01:19:26Z",
            "imsi": "001010000010003"
        }'
            curl -X 'PUT' \
        "$BASE_URL/ims_subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "ifc_path": "default_ifc.xml",   
            "sh_profile": "string",
            "pcscf": null, 
            "scscf": "sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060",
            "pcscf_realm": null,
            "scscf_timestamp": "2024-10-02 16:46:14",
            "pcscf_active_session": null,
            "scscf_realm": "ims.mnc001.mcc001.3gppnetwork.org",
            "ims_subscriber_id": 4,
            "pcscf_timestamp": null,
            "scscf_peer": "scscf.ims.mnc001.mcc001.3gppnetwork.org;hss.ims.mnc001.mcc001.3gppnetwork.org",
            "msisdn": "10004",
            "pcscf_peer": null,
            "sh_template_path": null,
            "msisdn_list": "[10004]",
            "xcap_profile": null,
            "last_modified": "2024-10-22T01:19:26Z",
            "imsi": "001010000010004"
        }'
            curl -X 'PUT' \
        "$BASE_URL/ims_subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "ifc_path": "default_ifc.xml",   
            "sh_profile": "string",
            "pcscf": null, 
            "scscf": "sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060",
            "pcscf_realm": null,
            "scscf_timestamp": "2024-10-02 16:46:14",
            "pcscf_active_session": null,
            "scscf_realm": "ims.mnc001.mcc001.3gppnetwork.org",
            "ims_subscriber_id": 5,
            "pcscf_timestamp": null,
            "scscf_peer": "scscf.ims.mnc001.mcc001.3gppnetwork.org;hss.ims.mnc001.mcc001.3gppnetwork.org",
            "msisdn": "10005",
            "pcscf_peer": null,
            "sh_template_path": null,
            "msisdn_list": "[10005]",
            "xcap_profile": null,
            "last_modified": "2024-10-22T01:19:26Z",
            "imsi": "001010000010005"
        }'
            curl -X 'PUT' \
        "$BASE_URL/ims_subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "ifc_path": "default_ifc.xml",   
            "sh_profile": "string",
            "pcscf": null, 
            "scscf": "sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060",
            "pcscf_realm": null,
            "scscf_timestamp": "2024-10-02 16:46:14",
            "pcscf_active_session": null,
            "scscf_realm": "ims.mnc001.mcc001.3gppnetwork.org",
            "ims_subscriber_id": 6,
            "pcscf_timestamp": null,
            "scscf_peer": "scscf.ims.mnc001.mcc001.3gppnetwork.org;hss.ims.mnc001.mcc001.3gppnetwork.org",
            "msisdn": "10006",
            "pcscf_peer": null,
            "sh_template_path": null,
            "msisdn_list": "[10006]",
            "xcap_profile": null,
            "last_modified": "2024-10-22T01:19:26Z",
            "imsi": "001010000010006"
        }'
            curl -X 'PUT' \
        "$BASE_URL/ims_subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "ifc_path": "default_ifc.xml",   
            "sh_profile": "string",
            "pcscf": null, 
            "scscf": "sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060",
            "pcscf_realm": null,
            "scscf_timestamp": "2024-10-02 16:46:14",
            "pcscf_active_session": null,
            "scscf_realm": "ims.mnc001.mcc001.3gppnetwork.org",
            "ims_subscriber_id": 7,
            "pcscf_timestamp": null,
            "scscf_peer": "scscf.ims.mnc001.mcc001.3gppnetwork.org;hss.ims.mnc001.mcc001.3gppnetwork.org",
            "msisdn": "10007",
            "pcscf_peer": null,
            "sh_template_path": null,
            "msisdn_list": "[10007]",
            "xcap_profile": null,
            "last_modified": "2024-10-22T01:19:26Z",
            "imsi": "001010000010007"
        }'
            curl -X 'PUT' \
        "$BASE_URL/ims_subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "ifc_path": "default_ifc.xml",   
            "sh_profile": "string",
            "pcscf": null, 
            "scscf": "sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060",
            "pcscf_realm": null,
            "scscf_timestamp": "2024-10-02 16:46:14",
            "pcscf_active_session": null,
            "scscf_realm": "ims.mnc001.mcc001.3gppnetwork.org",
            "ims_subscriber_id": 8,
            "pcscf_timestamp": null,
            "scscf_peer": "scscf.ims.mnc001.mcc001.3gppnetwork.org;hss.ims.mnc001.mcc001.3gppnetwork.org",
            "msisdn": "10008",
            "pcscf_peer": null,
            "sh_template_path": null,
            "msisdn_list": "[10008]",
            "xcap_profile": null,
            "last_modified": "2024-10-22T01:19:26Z",
            "imsi": "001010000010008"
        }'
            curl -X 'PUT' \
        "$BASE_URL/ims_subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "ifc_path": "default_ifc.xml",   
            "sh_profile": "string",
            "pcscf": null, 
            "scscf": "sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060",
            "pcscf_realm": null,
            "scscf_timestamp": "2024-10-02 16:46:14",
            "pcscf_active_session": null,
            "scscf_realm": "ims.mnc001.mcc001.3gppnetwork.org",
            "ims_subscriber_id": 9,
            "pcscf_timestamp": null,
            "scscf_peer": "scscf.ims.mnc001.mcc001.3gppnetwork.org;hss.ims.mnc001.mcc001.3gppnetwork.org",
            "msisdn": "10009",
            "pcscf_peer": null,
            "sh_template_path": null,
            "msisdn_list": "[10009]",
            "xcap_profile": null,
            "last_modified": "2024-10-22T01:19:26Z",
            "imsi": "001010000010009"
        }'
            curl -X 'PUT' \
        "$BASE_URL/ims_subscriber/" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{
            "ifc_path": "default_ifc.xml",   
            "sh_profile": "string",
            "pcscf": null, 
            "scscf": "sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060",
            "pcscf_realm": null,
            "scscf_timestamp": "2024-10-02 16:46:14",
            "pcscf_active_session": null,
            "scscf_realm": "ims.mnc001.mcc001.3gppnetwork.org",
            "ims_subscriber_id": 10,
            "pcscf_timestamp": null,
            "scscf_peer": "scscf.ims.mnc001.mcc001.3gppnetwork.org;hss.ims.mnc001.mcc001.3gppnetwork.org",
            "msisdn": "10010",
            "pcscf_peer": null,
            "sh_template_path": null,
            "msisdn_list": "[10010]",
            "xcap_profile": null,
            "last_modified": "2024-10-22T01:19:26Z",
            "imsi": "001010000010010"
        }'
}
function print_help() {
  echo_info "This script compiles OpenAirInterface Software, and can iinstall dependencies
Options: 
-I 
   Install prerequisites
-volte
   Install and build images/containers ffor volte
-uhd 
   Install UHD for usrp at host
-hss   Install user at the hss container
-osmohlr
   Instal user at the osmohlr container
-pyhss
   Configure APNS, AUCs, subscribers and IMS subscribers
-showAPNspyhss
   Show all APNs at pyhss
-showAUCspyhss
   Show all AUCs at pyhss
-showAsubscriberspyhss
   Show all subscribers at pyhss
-showIMSsubscriberspyhss
   Show all IMS subscribers at pyhss
-testusrp
   Test if usrp is connected to the computer
-aoi
   Install all software and configure subscribers
-h
   Print this help"
}
function update_env_file() {
    # Get the current IP address of the computer
    local ip_address=$(hostname -I | awk '{print $1}')

    # Path to the .env file
    local env_file="$HOME/docker_open5gs/.env"

    # Check if the .env file exists
    if [[ ! -f "$env_file" ]]; then
        echo ".env file not found at $env_file"
        return 1
    fi

    # Use sed to replace the IP addresses in the .env file
    sed -i.bak "s/^DOCKER_HOST_IP=.*/DOCKER_HOST_IP=$ip_address/" "$env_file"
    sed -i.bak "s/^SGWU_ADVERTISE_IP=.*/SGWU_ADVERTISE_IP=$ip_address/" "$env_file"

    echo "Updated .env file with new IP: $ip_address"
}
function main() {

  until [ -z "$1" ]
  do
    case "$1" in
       -I | --installation)
		# Install the latest version of docker
		# Set up docker apt repository
		# Add Docker's official GPG key:
		sudo apt-get update
		sudo apt-get install ca-certificates curl
		sudo install -m 0755 -d /etc/apt/keyrings
		sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
		sudo chmod a+r /etc/apt/keyrings/docker.asc
		# Add the repository to Apt sources:
		echo \
  		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  		$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
		sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
		sudo apt-get update
		# Install docker using apt
		sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker compose-plugin docker compose git -y
		sudo groupadd docker
		sudo usermod -aG docker $USER
		newgrp docker
		docker --version
		docker compose --version
            exit 1;;
       -uhd | --uhd)
		sudo apt-get install libuhd-dev uhd-host
            exit 1;;
       -aio | --aio)
       		update_env_file
                install_dependencies
		build_images
		uhd_installation_host
		deploying
		hss_configuration
		osmohlr_configuration
		local ip_address=$(get_ip_address)  # Get the IP address
    		local port="8080"                     # Define the port
		pyhss_configuration "$ip_address" "$port"
		echo "Installation completed, now install SIM cards into the smartphones and connect the usrp to the computer"
            exit 1;;
       -testusrp | --testusrp)
                sudo uhd_find_devices
            exit 1;;
       -hss | --hss)
		hss_configuration
            exit 1;;
       -volte | --voltecuatrog)
            	build_images
		deploying
            exit 1;;
	-osmohlr | --osmohlr)
		osmohlr_configuration
		exit 1;;
        -showAPNspyhss | --showAPNspyhss)
                docker exec -it pyhss curl -X 'GET' \
  'http://192.168.23.219:8080/apn/list?page=0&page_size=200' \
  -H 'accept: application/json'
            exit 1;;
        -showAUCspyhss | --showAUCspyhss)
                docker exec -it pyhss curl -X 'GET' \
  'http://192.168.23.219:8080/auc/list?page=0&page_size=200' \
  -H 'accept: application/json'
            exit 1;;
        -showsubscriberspyhss | --showsubscriberspyhss)
                docker exec -it pyhss curl -X 'GET' \
  'http://192.168.23.219:8080/subscriber/list?page=0&page_size=200' \
  -H 'accept: application/json'
            exit 1;;
        -showIMSsubscriberspyhss | --showIMSsubscriberspyhss)
                docker exec -it pyhss curl -X 'GET' \
  'http://192.168.23.219:8080/ims_subscriber/list?page=0&page_size=200' \
  -H 'accept: application/json'
            exit 1;;
        -pyhss | --pyhss)
		local ip_address=$(get_ip_address)  # Get the IP address
    		local port="8080"                     # Define the port
		pyhss_configuration "$ip_address" "$port"
            exit 1;;
       -h | --help)
            print_help
            exit 1;;
        *)
            print_help
            echo_fatal "Unknown option $1"
            break;;
   esac
  done
}
main "$@"
