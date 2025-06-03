#!/bin/bash

echo "=== 🚀 Drosera One-Click Setup (Trap + Operator) ==="

# === **Saint Khen** ===
echo -e "\n\033[1mSaint Khen\033[0m\n"

# Function to trim whitespace
trim() {
  echo "$1" | xargs
}

# Basic validation for private key (should be 64 hex chars)
validate_private_key() {
  if [[ ! $1 =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "❌ Invalid private key format. Must be exactly 64 hex characters."
    exit 1
  fi
}

# Basic validation for IP address
validate_ip() {
  if ! [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "❌ Invalid IP address format."
    exit 1
  fi
}

# Prompt inputs and trim
read -p "Enter your Trap EVM Private Key (64 hex chars): " PRIVATE_KEY
PRIVATE_KEY=$(trim "$PRIVATE_KEY")
validate_private_key "$PRIVATE_KEY"

read -p "Enter your Ethereum Holesky RPC URL (Alchemy/QuickNode): " RPC_URL
RPC_URL=$(trim "$RPC_URL")

read -p "Enter your GitHub Email: " GITHUB_EMAIL
GITHUB_EMAIL=$(trim "$GITHUB_EMAIL")

read -p "Enter your GitHub Username: " GITHUB_USER
GITHUB_USER=$(trim "$GITHUB_USER")

read -p "Enter your Operator Address (0x...): " OPERATOR_ADDR
OPERATOR_ADDR=$(trim "$OPERATOR_ADDR")

read -p "Enter your VPS Public IP (for P2P): " VPS_IP
VPS_IP=$(trim "$VPS_IP")
validate_ip "$VPS_IP"

read -p "Install operator using Docker or SystemD? (docker/systemd): " INSTALL_METHOD
INSTALL_METHOD=$(trim "$INSTALL_METHOD")
if [[ "$INSTALL_METHOD" != "docker" && "$INSTALL_METHOD" != "systemd" ]]; then
  echo "❌ Invalid install method. Choose 'docker' or 'systemd'."
  exit 1
fi

echo -e "\n🔄 Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev ca-certificates gnupg

echo -e "\n🐳 Installing Docker..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove -y $pkg; done

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo -e "\n🔧 Installing CLI tools (Drosera, Foundry, Bun)..."
curl -L https://app.drosera.io/install | bash && source ~/.bashrc && droseraup
curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup
curl -fsSL https://bun.sh/install | bash && source ~/.bashrc

echo -e "\n📂 Cloning and building Trap project..."
mkdir -p ~/my-drosera-trap && cd ~/my-drosera-trap
git config --global user.email "$GITHUB_EMAIL"
git config --global user.name "$GITHUB_USER"

forge init -t drosera-network/trap-foundry-template
bun install
forge build

echo -e "\n📝 Creating drosera.toml config..."
cat <<EOF > drosera.toml
private_trap = true
whitelist = ["$OPERATOR_ADDR"]
EOF

echo -e "\n🚀 Deploying Trap with drosera CLI..."
DROSERA_PRIVATE_KEY="$PRIVATE_KEY" drosera apply --eth-rpc-url "$RPC_URL"

echo -e "\n⬇️ Downloading drosera-operator binary..."
cd ~
curl -LO https://github.com/drosera-network/releases/releases/download/v1.17.2/drosera-operator-v1.17.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.17.2-x86_64-unknown-linux-gnu.tar.gz
sudo cp drosera-operator /usr/bin

echo -e "\n🔐 Registering Operator..."
drosera-operator register --eth-rpc-url "$RPC_URL" --eth-private-key "$PRIVATE_KEY"

echo -e "\n🛡️ Setting up firewall rules..."
sudo ufw allow ssh
sudo ufw allow 22
sudo ufw allow 31313/tcp
sudo ufw allow 31314/tcp
sudo ufw --force enable

echo -e "\n📦 Creating .env file for Docker..."
cat <<EOF > ~/my-drosera-trap/.env
EVM_PRIVATE_KEY=$PRIVATE_KEY
VPS_PUBLIC_IP=$VPS_IP
ETH_RPC_URL=$RPC_URL
EOF

if [[ "$INSTALL_METHOD" == "docker" ]]; then
  echo -e "\n🐳 Installing Drosera Operator with Docker..."

  if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker before proceeding."
    exit 1
  fi

  cd ~
  if [ ! -d "Drosera-Network" ]; then
    git clone https://github.com/0xmoei/Drosera-Network
  fi
  cd Drosera-Network

  cp .env.example .env

  # ✅ Escape the private key before using sed
  escaped_key=$(printf '%s\n' "$PRIVATE_KEY" | sed -e 's/[\/&]/\\&/g')
  sed -i "s|your_evm_private_key|$escaped_key|g" .env
  sed -i "s|your_vps_public_ip|$VPS_IP|g" .env
  sed -i "s|https://ethereum-holesky-rpc.publicnode.com|$RPC_URL|g" docker-compose.yaml

  echo -e "\n📢 Starting Docker containers..."
  docker compose up -d

else
  echo -e "\n⚙️ Installing Drosera Operator as a systemd service..."

  sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=drosera node service
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=/usr/bin/drosera-operator node --db-file-path $HOME/.drosera.db --network-p2p-port 31313 --server-port 31314 \
--eth-rpc-url $RPC_URL \
--eth-backup-rpc-url https://1rpc.io/holesky \
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
  sudo systemctl start drosera
fi

echo -e "\n✅ All done!"
echo "🌐 Go to https://app.drosera.io and connect your wallet"
echo "🧠 If you haven't opted-in yet, use the Dashboard to 'Opt-in' your Trap"
echo "🛠️ Use: journalctl -u drosera.service -f  OR  docker logs -f drosera-node"
