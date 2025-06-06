#!/bin/bash

echo "=== 🚀 Drosera One-Click Setup (Trap + Operator) ==="
echo -e "\n\033[1mSaint Khen\033[0m\n"

# Trim whitespace
trim() { echo "$1" | xargs; }

# Validate private key (allow 0x prefix, strip it)
validate_private_key() {
    local key=$1
    if [[ $key == 0x* ]]; then
        key=${key:2} # Strip 0x prefix
    fi
    if [[ ! $key =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo "❌ Invalid private key format (must be 64 hex chars, 0x prefix optional)."
        exit 1
    fi
    echo $key
}

# Validate IP address
validate_ip() {
    if ! [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "❌ Invalid IP address."
        exit 1
    fi
}

# Check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "❌ $1 not found. Installation may have failed."
        exit 1
    fi
}

# Check for port conflicts using ss (fallback to netstat if available)
check_ports() {
    if command -v ss &> /dev/null; then
        if ss -tuln | grep -qE ':31313|:31314'; then
            echo "❌ Ports 31313 or 31314 are in use. Please free them or edit docker-compose.yaml to use different ports (e.g., 31315, 31316)."
            exit 1
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -tulnp | grep -qE ':31313|:31314'; then
            echo "❌ Ports 31313 or 31314 are in use. Please free them or edit docker-compose.yaml to use different ports (e.g., 31315, 31316)."
            exit 1
        fi
    else
        echo "⚠️ Neither ss nor netstat found. Please ensure ports 31313 and 31314 are free."
    fi
}

# === USER INPUT ===
echo "📝 Please provide the following details (press Enter to skip optional fields):"
read -p "Enter your Trap EVM Private Key (64 hex chars, 0x prefix optional): " PRIVATE_KEY
PRIVATE_KEY=$(trim "$PRIVATE_KEY")
PRIVATE_KEY=$(validate_private_key "$PRIVATE_KEY")

read -p "Enter your Ethereum Holesky RPC URL (optional, press Enter for default): " RPC_URL
RPC_URL=$(trim "$RPC_URL")
if [ -z "$RPC_URL" ]; then
    RPC_URL="https://eth-holesky.g.alchemy.com/v2/SDctBqvoTyj4LBriVGJPE"
    echo "ℹ️ Using default Alchemy RPC. For custom RPC, get one from Alchemy/QuickNode."
fi

read -p "Enter your GitHub Email (optional): " GITHUB_EMAIL
GITHUB_EMAIL=$(trim "$GITHUB_EMAIL")
read -p "Enter your GitHub Username (optional): " GITHUB_USER
GITHUB_USER=$(trim "$GITHUB_USER")

read -p "Enter your Operator Address (0x..., optional, auto-derived if blank): " OPERATOR_ADDR
OPERATOR_ADDR=$(trim "$OPERATOR_ADDR")
if [ -z "$OPERATOR_ADDR" ]; then
    OPERATOR_ADDR=$(cast wallet address --private-key $PRIVATE_KEY 2>/dev/null || echo "")
    if [ -z "$OPERATOR_ADDR" ]; then
        echo "❌ Failed to derive operator address. Please provide it manually."
        exit 1
    fi
    echo "ℹ️ Operator address auto-derived: $OPERATOR_ADDR"
fi

read -p "Enter your VPS Public IP: " VPS_IP
VPS_IP=$(trim "$VPS_IP")
validate_ip "$VPS_IP"

read -p "Install operator using Docker or SystemD? (docker/systemd, Enter for docker): " INSTALL_METHOD
INSTALL_METHOD=$(trim "$INSTALL_METHOD")
if [ -z "$INSTALL_METHOD" ] || [[ "$INSTALL_METHOD" != "systemd" ]]; then
    INSTALL_METHOD="docker"
fi

read -p "Enter your Discord username (e.g., admirkhen#1234, optional): " DISCORD_NAME
DISCORD_NAME=$(trim "$DISCORD_NAME")

# === SYSTEM SETUP ===
echo -e "\n🔄 Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev ca-certificates gnupg net-tools

# === DOCKER INSTALL ===
if command -v docker &> /dev/null; then
    echo "ℹ️ Docker already installed, skipping installation."
else
    echo -e "\n🐳 Installing Docker..."
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove -y $pkg; done
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo docker run hello-world || { echo "❌ Docker installation failed."; exit 1; }
fi

# === CHECK PORTS ===
echo -e "\n🔍 Checking for port conflicts..."
check_ports

# === TOOLS INSTALL ===
echo -e "\n🔧 Installing CLI tools (Drosera, Foundry, Bun)..."
# Drosera CLI
curl -L https://app.drosera.io/install | bash || { echo "❌ Drosera CLI installation failed. Check network or https://app.drosera.io/install."; exit 1; }
# Ensure PATH is updated
source ~/.bashrc 2>/dev/null || source ~/.bash_profile 2>/dev/null || { echo "❌ Failed to source bash configuration. Trying new shell..."; bash -c "source ~/.bashrc && droseraup"; }
if ! command -v droseraup &> /dev/null; then
    echo "❌ droseraup not found after installation. Retrying..."
    curl -L https://app.drosera.io/install | bash || { echo "❌ Drosera CLI retry failed."; exit 1; }
    source ~/.bashrc 2>/dev/null || source ~/.bash_profile 2>/dev/null
fi
droseraup || { echo "❌ droseraup failed. Check network or Drosera documentation."; exit 1; }
check_command drosera

# Foundry
curl -L https://foundry.paradigm.xyz | bash || { echo "❌ Foundry installation failed."; exit 1; }
source ~/.bashrc 2>/dev/null || source ~/.bash_profile 2>/dev/null
foundryup || { echo "❌ foundryup failed."; exit 1; }
check_command forge
check_command cast

# Bun
curl -fsSL https://bun.sh/install | bash || { echo "❌ Bun installation failed."; exit 1; }
source ~/.bashrc 2>/dev/null || source ~/.bash_profile 2>/dev/null
check_command bun

# === TRAP SETUP ===
echo -e "\n📂 Setting up Trap project..."
mkdir -p ~/my-drosera-trap && cd ~/my-drosera-trap
if [ ! -z "$GITHUB_EMAIL" ] && [ ! -z "$GITHUB_USER" ]; then
    git config --global user.email "$GITHUB_EMAIL"
    git config --global user.name "$GITHUB_USER"
fi
forge init -t drosera-network/trap-foundry-template || { echo "❌ forge init failed."; exit 1; }

# === CUSTOM TRAP CONTRACT ===
if [ ! -z "$DISCORD_NAME" ]; then
    echo -e "\n✍️ Writing custom Trap.sol ciliary
    cat <<EOF > ~/my-drosera-trap/src/Trap.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

interface IMockResponse {
    function isActive() external view returns (bool);
}

contract Trap is ITrap {
    address public constant RESPONSE_CONTRACT = 0x4608Afa7f277C8E0BE232232265850d1cDeB600E;
    string constant discordName = "$DISCORD_NAME";

    function collect() external view returns (bytes memory) {
        bool active = IMockResponse(RESPONSE_CONTRACT).isActive();
        return abi.encode(active, discordName);
    }

    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        (bool active, string memory name) = abi.decode(data[0], (bool, string));
        if (!active || bytes(name).length == 0) {
            return (false, bytes(""));
        }
        return (true, abi.encode(name));
    }
}
EOF
fi

# === CONFIG FIX ===
echo -e "\n🛠️ Updating drosera.toml config..."
cd ~/my-drosera-trap
if [ ! -f drosera.toml ]; then
    echo "❌ drosera.toml not found. Forge init may have failed."
    exit 1
fi
sed -i 's|path = .*|path = "out/Trap.sol/Trap.json"|' drosera.toml
if grep -q "^private *= *true" drosera.toml; then
    sed -i 's/^private *= *true/private_trap = true/' drosera.toml
else
    echo "private_trap = true" >> drosera.toml
fi
if ! grep -q "whitelist" drosera.toml; then
    echo "whitelist = [\"$OPERATOR_ADDR\"]" >> drosera.toml
fi
echo 'response_contract = "0x4608Afa7f277C8E0BE232232265850d1cDeB600E"' >> drosera.toml
echo 'response_function = "respondWithDiscordName(string)"' >> drosera.toml

# === BUILD + DEPLOY ===
echo -e "\n🔨 Building trap..."
bun install || { echo "❌ bun install failed."; exit 1; }
forge build || { echo "❌ forge build failed."; exit 1; }

echo -e "\n🚀 Deploying Trap with drosera CLI..."
DROSERA_PRIVATE_KEY="$PRIVATE_KEY" drosera apply --eth-rpc-url "$RPC_URL" || { echo "❌ Trap deployment failed. Check private key or RPC URL (ensure wallet has Holesky ETH)."; exit 1; }

# === OPERATOR SETUP ===
echo -e "\n⬇️ Downloading drosera-operator..."
cd ~
curl -LO https://github.com/drosera-network/releases/releases/download/v1.17.2/drosera-operator-v1.17.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.17.2-x86_64-unknown-linux-gnu.tar.gz
sudo cp drosera-operator /usr/bin
check_command drosera-operator

echo -e "\n🔐 Registering Operator..."
drosera-operator register --eth-rpc-url "$RPC_URL" --eth-private-key "$PRIVATE_KEY" || { echo "❌ Operator registration failed. Check private key or RPC URL."; exit 1; }

# === FIREWALL ===
echo -e "\n🛡️ Configuring UFW..."
sudo ufw allow ssh
sudo ufw allow 22
sudo ufw allow 31313/tcp
sudo ufw allow 31314/tcp
sudo ufw --force enable

# === INSTALL MODE ===
if [[ "$INSTALL_METHOD" == "docker" ]]; then
    echo -e "\n🐳 Setting up Docker operator..."
    cd ~
    [ -d "Drosera-Network" ] || git clone https://github.com/0xmoei/Drosera-Network
    cd Drosera-Network
    cat <<EOF > .env
ETH_PRIVATE_KEY=$PRIVATE_KEY
VPS_IP=$VPS_IP
EOF
    cat <<EOF > docker-compose.yaml
version: '3'
services:
  drosera:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node-unique
    network_mode: host
    volumes:
      - drosera_data_unique:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31313 --server-port 31314 --eth-rpc-url $RPC_URL --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key \${ETH_PRIVATE_KEY} --listen-address 0.0.0.0 --network-external-p2p-address \${VPS_IP} --disable-dnr-confirmation true
    restart: always
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512m
volumes:
  drosera_data_unique:
EOF
    docker compose up -d || { echo "❌ Docker operator failed to start. Check Docker setup or port conflicts."; exit 1; }
else
    echo -e "\n⚙️ Setting up SystemD service..."
    sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=Drosera Operator Node
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=/usr/bin/drosera-operator node --db-file-path $HOME/.drosera.db --network-p2p-port 31313 --server-port 31314 \
    --eth-rpc-url $RPC_URL \
    --eth-backup-rpc-url https://holesky.drpc.org \
    --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \
    --eth-private-key $PRIVATE_KEY \
    --listen-address 0.0.0.0 \
    --network-external-p2p-address $VPS_IP \
    --disable-dnr-confirmation true

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable drosera
    sudo systemctl start drosera || { echo "❌ SystemD operator failed to start. Check private key or RPC URL."; exit 1; }
fi

# === VERIFY ===
echo -e "\n🔍 Verifying Trap registration..."
OWNER_ADDR=$(cast wallet address --private-key $PRIVATE_KEY 2>/dev/null || echo "")
if [ -z "$OWNER_ADDR" ]; then
    echo "❌ Failed to derive owner address for verification."
    exit 1
fi
RESULT=$(cast call 0x4608Afa7f277C8E0BE232232265850d1cDeB600E "isResponder(address)(bool)" $OWNER_ADDR --rpc-url $RPC_URL 2>/dev/null || echo "false")
if [[ "$RESULT" == "true" ]]; then
    echo "✅ Trap registration verified!"
else
    echo "⚠️ Trap verification failed. It may take a few minutes. Check again with:"
    echo "cast call 0x4608Afa7f277C8E0BE232232265850d1cDeB600E \"isResponder(address)(bool)\" $OWNER_ADDR --rpc-url $RPC_URL"
fi

# === DONE ===
echo -e "\n✅ Setup complete!"
echo "🌐 Go to https://app.drosera.io, connect your wallet, and opt-in your operator."
echo "📦 Check trap status and set Bloom on the dashboard."
if [[ "$INSTALL_METHOD" == "docker" ]]; then
    echo "🧠 View logs: docker logs -f drosera-node-unique"
    echo "🔄 Restart if needed: cd ~/Drosera-Network && docker compose down -v && docker compose up -d"
else
    echo "🧠 View logs: journalctl -u drosera.service -f"
    echo "🔄 Restart if needed: sudo systemctl restart drosera"
fi
echo "⚠️ If you see white blocks, check your RPC or restart the operator."
echo "📢 For support, join the Drosera Discord community."
