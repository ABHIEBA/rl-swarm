#!/bin/bash

# General args
ROOT=$PWD

export PUB_MULTI_ADDRS
export PEER_MULTI_ADDRS
export HOST_MULTI_ADDRS
export IDENTITY_PATH
export CONNECT_TO_TESTNET
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120  # 2 minutes

# Check if public multi-address is given else set to default
DEFAULT_PUB_MULTI_ADDRS=""
PUB_MULTI_ADDRS=${PUB_MULTI_ADDRS:-$DEFAULT_PUB_MULTI_ADDRS}

# Check if peer multi-address is given else set to default
DEFAULT_PEER_MULTI_ADDRS="/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ" # gensyn coordinator node
PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-$DEFAULT_PEER_MULTI_ADDRS}

# Check if host multi-address is given else set to default
DEFAULT_HOST_MULTI_ADDRS="/ip4/0.0.0.0/tcp/38331"
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-$DEFAULT_HOST_MULTI_ADDRS}

# Path to an RSA private key. If this path does not exist, a new key pair will be created.
# Remove this file if you want a new PeerID.
DEFAULT_IDENTITY_PATH="$ROOT"/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

while true; do
    read -p "Would you like to connect to the Testnet? [Y/n] " yn
    yn=${yn:-Y}  # Default to "Y" if the user presses Enter
    case $yn in
        [Yy]* ) CONNECT_TO_TESTNET=True && break;;
        [Nn]* ) CONNECT_TO_TESTNET=False && break;;
        * ) echo ">>> Please answer yes or no.";;
    esac
done

if [ "$CONNECT_TO_TESTNET" = "True" ]; then
    # Run modal_login server
    echo "Please login to create an Ethereum Server Wallet"
    cd modal-login
    # Check if the yarn command exists; if not, install Yarn.
    source ~/.bashrc
    if ! command -v yarn >/dev/null 2>&1; then
      echo "Yarn is not installed. Installing Yarn..."
      curl -o- -L https://yarnpkg.com/install.sh | sh
      echo 'export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"' >> ~/.bashrc
      source ~/.bashrc
    fi
    yarn install
    yarn dev > /dev/null 2>&1 & # Run in background and suppress output
    SERVER_PID=$!  # Store the process ID
    sleep 5

    # Colors for better readability
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color

    # Function to display step headers
    print_step() {
        echo -e "\n${BLUE}${BOLD}Step $1: $2${NC}"
    }

    # Function to check if command was successful
    check_success() {
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Success!${NC}"
        else
            echo -e "${RED}✗ Failed! Please check errors above and try again.${NC}"
            exit 1
        fi
    }

    # Detect architecture
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
        echo "Please download ngrok manually from https://ngrok.com/download"
        exit 1
    fi

    # Download and install ngrok
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
    
        # Authenticate ngrok
        ngrok authtoken "$NGROK_TOKEN"
        
        # Check if authentication was successful
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Successfully authenticated ngrok!${NC}"
            break
        else
            echo -e "${RED}✗ Authentication failed. Please check your token and try again.${NC}"
        fi
    done

    # Start ngrok tunnel
    print_step 4 "Starting ngrok tunnel on port 3000"
    echo -e "${YELLOW}Starting ngrok HTTPS tunnel forwarding localhost:3000...${NC}"
    # Ensure no existing ngrok processes are running
    pkill -f ngrok
    sleep 2
    # Start ngrok in background, forwarding to localhost:3000
    ngrok http 3000 --log=stdout >/dev/null 2>&1 &
    NGROK_PID=$!
    # Wait for ngrok to start (30 seconds max)
    echo -n "Waiting for ngrok to initialize"
    MAX_WAIT=30
    counter=0
    while [ $counter -lt $MAX_WAIT ]; do
        echo -n "."
        sleep 1
        # Check if the API is ready
        if curl -s http://localhost:4040/api/tunnels >/dev/null; then
            echo " Ready!"
            break
        fi
        counter=$((counter + 1))
    done

    if [ $counter -eq $MAX_WAIT ]; then
        echo -e "\n${RED}Timeout waiting for ngrok to start.${NC}"
        kill $NGROK_PID 2>/dev/null || true
        exit 1
    fi

    TUNNEL_INFO=$(curl -s http://localhost:4040/api/tunnels)
    FORWARDING_URL=$(echo "$TUNNEL_INFO" | grep -o '"public_url":"https://[^"]*' | head -n1 | cut -d'"' -f4)
    if [ -z "$FORWARDING_URL" ]; then
        echo -e "${RED}Failed to get forwarding URL from ngrok API.${NC}"
        kill $NGROK_PID 2>/dev/null || true
        exit 1
    else
        echo -e "\n${GREEN}${BOLD}✓ Success! Visit this website and login using your email${NC} : ${BLUE}${BOLD}${FORWARDING_URL}${NC}"
    fi

    cd ..
    # Wait until modal-login/temp-data/userData.json exists
    while [ ! -f "modal-login/temp-data/userData.json" ]; do
        echo "Waiting for userData.json to be created..."
        sleep 5  # Wait for 5 seconds before checking again
    done
    echo "userData.json found. Proceeding..."

    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
    echo "ORG_ID set to: $ORG_ID"

    # Function to clean up the server and ngrok processes
    cleanup() {
        echo "Shutting down server and ngrok..."
        kill $SERVER_PID 2>/dev/null || true
        kill $NGROK_PID 2>/dev/null || true
        exit 0
    }

    # Set up trap to catch Ctrl+C and call cleanup
    trap cleanup INT
fi

# Let's go!
echo "Getting requirements..."
pip install -r "$ROOT"/requirements-hivemind.txt > /dev/null
pip install -r "$ROOT"/requirements.txt > /dev/null

if ! which nvidia-smi; then
   # You don't have a NVIDIA GPU
   CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
elif [ -n "$CPU_ONLY" ]; then
   # ... or we don't want to use it
   CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
else
   # NVIDIA GPU found
   pip install -r "$ROOT"/requirements_gpu.txt > /dev/null
   CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
fi

echo ">> Done!"
echo ""
echo ""

if [ -n "${HF_TOKEN}" ]; then # Check if HF_TOKEN is already set and use if so. Else give user a prompt to choose.
   HUGGINGFACE_ACCESS_TOKEN=${HF_TOKEN}
else
   read -p "Would you like to push models you train in the RL swarm to the Hugging Face Hub? [y/N] " yn
   yn=${yn:-N}  # Default to "N" if the user presses Enter
   case $yn in
      [Yy]* ) read -p "Enter your Hugging Face access token: " HUGGINGFACE_ACCESS_TOKEN;;
      [Nn]* ) HUGGINGFACE_ACCESS_TOKEN="None";;
      * ) echo ">>> No answer was given, so NO models will be pushed to Hugging Face Hub" && HUGGINGFACE_ACCESS_TOKEN="None";;
   esac
fi

echo ""
echo ""
echo "Good luck in the swarm!"

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

wait  # Keep script running until Ctrl+C
