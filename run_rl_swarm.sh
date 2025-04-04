#!/bin/bash

# Set the root directory to the current working directory
ROOT=$PWD

# Export environment variables
export PUB_MULTI_ADDRS
export PEER_MULTI_ADDRS
export HOST_MULTI_ADDRS
export IDENTITY_PATH
export CONNECT_TO_TESTNET
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120

# Set default values for environment variables if not already defined
DEFAULT_PUB_MULTI_ADDRS=""
PUB_MULTI_ADDRS=${PUB_MULTI_ADDRS:-$DEFAULT_PUB_MULTI_ADDRS}

DEFAULT_PEER_MULTI_ADDRS="/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ"
PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-$DEFAULT_PEER_MULTI_ADDRS}

DEFAULT_HOST_MULTI_ADDRS="/ip4/0.0.0.0/tcp/38331"
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-$DEFAULT_HOST_MULTI_ADDRS}

DEFAULT_IDENTITY_PATH="$ROOT"/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

# Prompt user to connect to Testnet
while true; do
    read -p "Would you like to connect to the Testnet? [Y/n] " yn
    yn=${yn:-Y}
    case $yn in
        [Yy]* ) CONNECT_TO_TESTNET=True && break;;
        [Nn]* ) CONNECT_TO_TESTNET=False && break;;
        * ) echo ">>> Please answer yes or no.";;
    esac
done

if [ "$CONNECT_TO_TESTNET" = "True" ]; then
    echo "Please login to create an Ethereum Server Wallet"
    cd modal-login
    source ~/.bashrc

    # Install npm if not present
    if ! command -v npm >/dev/null 2>&1; then
        echo "npm is not installed. Installing Node.js and npm..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt-get install -y nodejs
        source ~/.bashrc
    fi
    
    echo "Installing dependencies with npm (may take few mins, depend on your internet speed)..."
    npm install --legacy-peer-deps

    # Start the development server in the background
    echo "Starting the development server..."
    npm run dev > server.log 2>&1 &
    SERVER_PID=$!
    
    echo "Waiting for server to start..."
    MAX_WAIT=60
    counter=0
    while [ $counter -lt $MAX_WAIT ]; do
        if grep -q "Local:        http://localhost:" server.log; then
            PORT=$(grep "Local:        http://localhost:" server.log | sed -n 's/.*http:\/\/localhost:\([0-9]*\).*/\1/p')
            if [ -n "$PORT" ]; then
                echo "Server is running on port $PORT"
                break
            fi
        fi
        sleep 1
        counter=$((counter + 1))
    done
    
    if [ $counter -eq $MAX_WAIT ]; then
        echo "Timeout waiting for server to start."
        echo "Contents of server.log:"
        cat server.log
        kill $SERVER_PID 2>/dev/null || true
        exit 1
    fi

    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
    
    print_step() {
        echo -e "\n${BLUE}${BOLD}Step $1: $2${NC}"
    }
    
    check_success() {
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Success!${NC}"
        else
            echo -e "${RED}✗ Failed! Please check errors above and try again.${NC}"
            exit 1
        fi
    }
    
    print_step 1 "Detecting system architecture"
    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    if [ "$ARCH" = "x86_64" ]; then
        NGROK_ARCH="amd64"
        echo "Detected x86_64 architecture"
    elif [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
        NGROK_ARCH="arm64"
        echo "Detected ARM64 architecture"
    elif [[ "$ARCH" == arm* ]]; then
        NGROK_ARCH="arm"
        echo "Detected ARM architecture"
    else
        echo -e "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
    fi
    
    print_step 2 "Downloading and installing ngrok"
    echo -e "Downloading ngrok for $OS-$NGROK_ARCH..."
    wget -q --show-progress "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-$OS-$NGROK_ARCH.tgz"
    check_success
    
    echo "Extracting ngrok..."
    tar -xzf "ngrok-v3-stable-$OS-$NGROK_ARCH.tgz"
    check_success
    
    echo "Moving ngrok to /usr/local/bin/ (requires sudo)..."
    sudo mv ngrok /usr/local/bin/
    check_success
    
    echo "Cleaning up..."
    rm "ngrok-v3-stable-$OS-$NGROK_ARCH.tgz"
    check_success
    
    print_step 3 "Authenticating ngrok"
    while true; do
        echo -e "\n${YELLOW}To get your authtoken:${NC}"
        echo "1. Sign up or log in at https://dashboard.ngrok.com"
        echo "2. Go to 'Your Authtoken' section: https://dashboard.ngrok.com/get-started/your-authtoken"
        echo "3. Click on the eye icon to reveal your ngrok auth token"
        echo "4. Copy that auth token and paste in the below section"
        echo -e "\n${BOLD}Please enter your ngrok authtoken:${NC}"
        read -p "> " NGROK_TOKEN
        
        if [ -z "$NGROK_TOKEN" ]; then
            echo -e "${RED}No token provided. Please enter a valid token.${NC}"
            continue
        fi
        
        # Ensure any previous ngrok processes are killed before authentication
        pkill -f ngrok || true
        sleep 2
        
        ngrok authtoken "$NGROK_TOKEN"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Successfully authenticated ngrok!${NC}"
            break
        else
            echo -e "${RED}✗ Authentication failed. Please check your token and try again.${NC}"
        fi
    done
    
    print_step 4 "Preparing for ngrok tunnel"
    # Kill any existing ngrok processes
    echo "Terminating any existing ngrok processes..."
    pkill -f ngrok || true
    sleep 3
    
    # Find available ports for ngrok web interface
    NGROK_WEB_PORT=4040
    while lsof -i :$NGROK_WEB_PORT >/dev/null 2>&1; do
        echo -e "${YELLOW}Port $NGROK_WEB_PORT is in use, trying next port...${NC}"
        NGROK_WEB_PORT=$((NGROK_WEB_PORT + 1))
    done
    echo -e "${GREEN}Will use port $NGROK_WEB_PORT for ngrok web interface${NC}"
    
    print_step 5 "Starting ngrok tunnel on port $PORT"
    echo -e "${YELLOW}Starting ngrok HTTPS tunnel forwarding localhost:$PORT...${NC}"
    
    # Try multiple approaches to start ngrok and get the URL
    echo "Using primary approach with direct log capture..."
    
    # Start ngrok with specific web interface port
    ngrok http "$PORT" --log=stdout --log-format=json --log-level=info > ngrok_output.log 2>&1 &
    NGROK_PID=$!
    
    # Function to extract URL from various sources
    get_forwarding_url() {
        # Try to get URL from log file first
        FORWARDING_URL=$(grep -o '"url":"https://[^"]*' ngrok_output.log 2>/dev/null | head -n1 | cut -d'"' -f4)
        
        # If not found, try the API approach with the detected web port
        if [ -z "$FORWARDING_URL" ]; then
            for try_port in $(seq $NGROK_WEB_PORT $((NGROK_WEB_PORT + 5))); do
                if curl -s "http://localhost:$try_port/api/tunnels" >/dev/null 2>&1; then
                    FORWARDING_URL=$(curl -s "http://localhost:$try_port/api/tunnels" | grep -o '"public_url":"https://[^"]*' | head -n1 | cut -d'"' -f4)
                    if [ -n "$FORWARDING_URL" ]; then
                        echo -e "${GREEN}Found ngrok web interface at port $try_port${NC}"
                        break
                    fi
                fi
            done
        fi
        
        # If still not found, try old-style output parsing as last resort
        if [ -z "$FORWARDING_URL" ]; then
            FORWARDING_URL=$(grep -m 1 "Forwarding" ngrok_output.log 2>/dev/null | grep -o "https://[^ ]*")
        fi
        
        echo "$FORWARDING_URL"
    }
    
    echo "Waiting for ngrok to initialize"
    MAX_WAIT=5
    counter=0
    
    while [ $counter -lt $MAX_WAIT ]; do
        echo -n "."
        FORWARDING_URL=$(get_forwarding_url)
        
        if [ -n "$FORWARDING_URL" ]; then
            echo -e "\n${GREEN}✓ URL found!${NC}"
            break
        fi
        sleep 1
        counter=$((counter + 1))
    done
    
    # If primary approach failed, try alternative approach
    if [ -z "$FORWARDING_URL" ]; then
        echo -e "\n${YELLOW}Primary approach failed. Trying alternative approach...${NC}"
        
        # Kill existing ngrok process and try with explicit region and random port
        kill $NGROK_PID 2>/dev/null || true
        sleep 3
        
        # Try with a different random port for ngrok API
        RANDOM_PORT=$((10000 + RANDOM % 20000))
        echo "Starting ngrok on random port $RANDOM_PORT..."
        
        ngrok http --region us --log=stdout "$PORT" > ngrok_output_alt.log 2>&1 &
        NGROK_PID=$!
        
        sleep 10
        
        # Try multiple ways to get the URL
        FORWARDING_URL=$(grep -o '"url":"https://[^"]*' ngrok_output_alt.log 2>/dev/null | head -n1 | cut -d'"' -f4)
        
        if [ -z "$FORWARDING_URL" ]; then
            for check_port in $(seq 4040 4050); do
                if curl -s "http://localhost:$check_port/api/tunnels" >/dev/null 2>&1; then
                    FORWARDING_URL=$(curl -s "http://localhost:$check_port/api/tunnels" | grep -o '"public_url":"https://[^"]*' | head -n1 | cut -d'"' -f4)
                    if [ -n "$FORWARDING_URL" ]; then
                        break
                    fi
                fi
            done
        fi
    fi  
    
    if [ -n "$FORWARDING_URL" ]; then
        echo -e "${GREEN}${BOLD}✓ Success! Visit this website and login using your email${NC} : ${BLUE}${BOLD}${FORWARDING_URL}${NC}"
    else
        echo -e "\n${YELLOW}Don't worry, follow these instructions:\n${NC}"
        echo "1. Open Command Prompt on your PC."
        echo -e "2. Paste this command into Command Prompt: ssh -L 3000:localhost:$PORT $(whoami)@$(curl -s ifconfig.me)"
        echo "3. After that, visit this website and log in using your email: http://localhost:3000/"
        echo "4. The above website may take up to 1 minute to be fully ready."
        kill $NGROK_PID 2>/dev/null || true
    fi
    
    cd ..
    echo -e "\nWaiting for you to complete the login process..."
    while [ ! -f "modal-login/temp-data/userData.json" ]; do
        sleep 5
    done
    echo -e "\n${GREEN}${BOLD}✓ Success! userData.json found. Proceeding...${NC}"

    # Extract ORG_ID from userData.json
    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
    echo "ORG_ID set to: $ORG_ID"

    # Cleanup function for graceful shutdown
    cleanup() {
        echo "Shutting down server and ngrok..."
        kill $SERVER_PID 2>/dev/null || true
        kill $NGROK_PID 2>/dev/null || true
        exit 0
    }

    trap cleanup INT
fi

# Install Python requirements
echo "Getting requirements..."
pip install -r "$ROOT"/requirements-hivemind.txt > /dev/null
pip install -r "$ROOT"/requirements.txt > /dev/null

# Determine config path based on hardware
if ! which nvidia-smi; then
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
elif [ -n "$CPU_ONLY" ]; then
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
else
    pip install -r "$ROOT"/requirements_gpu.txt > /dev/null
    CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
fi

echo ">> Done!"
echo ""

# Handle Hugging Face token
if [ -n "${HF_TOKEN}" ]; then
    HUGGINGFACE_ACCESS_TOKEN=${HF_TOKEN}
else
    read -p "Would you like to push models you train in the RL swarm to the Hugging Face Hub? [y/N] " yn
    yn=${yn:-N}
    case $yn in
        [Yy]* ) read -p "Enter your Hugging Face access token: " HUGGINGFACE_ACCESS_TOKEN;;
        [Nn]* ) HUGGINGFACE_ACCESS_TOKEN="None";;
        * ) echo ">>> No answer was given, so NO models will be pushed to Hugging Face Hub" && HUGGINGFACE_ACCESS_TOKEN="None";;
    esac
fi

echo ""
echo "Good luck in the swarm!"

# Run the Python training script with appropriate parameters
if [ -n "$ORG_ID" ]; then
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --modal_org_id "$ORG_ID" \
        --config "$CONFIG_PATH"
else
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --public_maddr "$PUB_MULTI_ADDRS" \
        --initial_peers "$PEER_MULTI_ADDRS" \
        --host_maddr "$HOST_MULTI_ADDRS" \
        --config "$CONFIG_PATH"
fi

wait
