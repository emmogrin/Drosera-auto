#!/bin/bash

echo "=== 🚀 Drosera One-Click Setup (Trap + Operator) ==="

# === **Saint Khen** ===
echo -e "\n\033[1mSaint Khen\033[0m\n"

# Prompt inputs
read -p "Enter your Trap EVM Private Key: " PRIVATE_KEY
read -p "Enter your Ethereum Holesky RPC URL (Alchemy/QuickNode): " RPC_URL
read -p "Enter your GitHub Email: " GITHUB_EMAIL
read -p "Enter your GitHub Username: " GITHUB_USER
read -p "Enter your Operator Address (0x...): " OPERATOR_ADDR
read -p "Enter your VPS Public IP (for P2P): " VPS_IP
read -p "Install operator using Docker or SystemD? (docker/systemd): " INSTALL_METHOD

# ----------------------------
# Step 1: Install Dependencies
# ----------------------------
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev ca-certificates gnupg

# ----------------------------
# Step 2: Install Docker
# ----------------------------
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg -y; done

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ----------------------------
# Step 3: Install CLI Tools
# ----------------------------
# Drosera CLI
curl -L https://app.drosera.io/install | bash && source ~/.bashrc && droseraup

# Foundry
curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup

# Bun
curl -fsSL https://bun.sh/install | bash && source ~/.bashrc

# ----------------------------
# Step 4: Clone & Build Trap
# ----------------------------
mkdir -p ~/my-drosera-trap && cd ~/my-drosera-trap
git config --global user.email "$GITHUB_EMAIL"
git config --global user.name "$GITHUB_USER"
forge init -t drosera-network/trap-foundry-template

bun install
forge build

# ----------------------------
# Step 5: Configure drosera.toml
# ----------------------------
cat <<EOF > drosera.toml
private_trap = true
whitelist = ["$OPERATOR_ADDR"]
EOF

# ----------------------------
# Step 6: Deploy Trap
# ----------------------------
DROSERA_PRIVATE_KEY="$PRIVATE_KEY" drosera apply --eth-rpc-url "$RPC_URL"

# ----------------------------
# Step 7: Setup Operator Binary
# ----------------------------
cd ~
curl -LO https://github.com/drosera-network/releases/releases/download/v1.17.2/drosera-operator-v1.17.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.17.2-x86_64-unknown-linux-gnu.tar.gz
sudo cp drosera-operator /usr/bin

# Register Operator
drosera-operator register --eth-rpc-url "$RPC_URL" --eth-private-key "$PRIVATE_KEY"

# ----------------------------
# Step 8: Firewall Rules
# ----------------------------
sudo ufw allow ssh
sudo ufw allow 22
sudo ufw allow 31313/tcp
sudo ufw allow 31314/tcp
sudo ufw --force enable

# ----------------------------
# Step 9: Create .env for Docker
# ----------------------------
cat <<EOF > ~/my-drosera-trap/.env
EVM_PRIVATE_KEY=$PRIVATE_KEY
VPS_PUBLIC_IP=$VPS_IP
ETH_RPC_URL=$RPC_URL
EOF

# ----------------------------
# Step 10: Run Operator
# ----------------------------
if [[ "$INSTALL_METHOD" == "docker" ]]; then
  git clone https://github.com/0xmoei/Drosera-Network
  cd Drosera-Network
  cp .env.example .env
  
  # Replace placeholder values with actual inputs
  sed -i "s/your_evm_private_key/$PRIVATE_KEY/" .env
  sed -i "s/your_vps_public_ip/$VPS_IP/" .env
  sed -i "s|https://ethereum-holesky-rpc.publicnode.com|$RPC_URL|" docker-compose.yaml

  docker compose up -d
else
  sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=drosera node service
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=$(which drosera-operator) node --db-file-path $HOME/.drosera.db --network-p2p-port 31313 --server-port 31314 \
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

# ----------------------------
# Final Message
# ----------------------------
echo ""
echo "✅ All done!"
echo "🌐 Go to https://app.drosera.io and connect your wallet"
echo "🧠 If you haven't opted-in yet, use the Dashboard to 'Opt-in' your Trap"
echo "🛠️ Use: journalctl -u drosera.service -f  OR  docker logs -f drosera-node"
