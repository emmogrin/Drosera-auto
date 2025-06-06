#!/bin/bash

echo "=== 🚀 Drosera One-Click Setup (Trap + Operator) ==="
echo -e "\n\033[1mSaint Khen\033[0m\n"

# Trim whitespace
trim() { echo "$1" | xargs; }

# Validations
validate_private_key() {
  if [[ ! $1 =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "❌ Invalid private key format."
    exit 1
  fi
}
validate_ip() {
  if ! [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "❌ Invalid IP address."
    exit 1
  fi
}

# === USER INPUT ===
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

read -p "Enter your Discord username (e.g. admirkhen#1234): " DISCORD_NAME
DISCORD_NAME=$(trim "$DISCORD_NAME")

# === SYSTEM SETUP ===
echo -e "\n🔄 Updating system..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev ca-certificates gnupg

# === DOCKER INSTALL ===
echo -e "\n🐳 Installing Docker..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove -y $pkg; done
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# === TOOLS INSTALL ===
echo -e "\n🔧 Installing CLI tools (Drosera, Foundry, Bun)..."
curl -L https://app.drosera.io/install | bash && source ~/.bashrc && droseraup
curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup
curl -fsSL https://bun.sh/install | bash && source ~/.bashrc

# === TRAP SETUP ===
echo -e "\n📂 Setting up Trap project..."
mkdir -p ~/my-drosera-trap && cd ~/my-drosera-trap
git config --global user.email "$GITHUB_EMAIL"
git config --global user.name "$GITHUB_USER"
forge init -t drosera-network/trap-foundry-template

# === CUSTOM TRAP CONTRACT ===
echo -e "\n✍️ Writing custom Trap.sol with Discord username..."
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

# === CONFIG FIX ===
echo -e "\n🛠️ Updating drosera.toml config..."
cd ~/my-drosera-trap
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
bun install
forge build

echo -e "\n🚀 Deploying Trap with drosera CLI..."
DROSERA_PRIVATE_KEY="$PRIVATE_KEY" drosera apply --eth-rpc-url "$RPC_URL"

# === OPERATOR SETUP ===
echo -e "\n⬇️ Downloading drosera-operator..."
cd ~
curl -LO https://github.com/drosera-network/releases/releases/download/v1.17.2/drosera-operator-v1.17.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.17.2-x86_64-unknown-linux-gnu.tar.gz
sudo cp drosera-operator /usr/bin

echo -e "\n🔐 Registering Operator..."
drosera-operator register --eth-rpc-url "$RPC_URL" --eth-private-key "$PRIVATE_KEY"

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
EVM_PRIVATE_KEY=$PRIVATE_KEY
VPS_PUBLIC_IP=$VPS_IP
ETH_RPC_URL=$RPC_URL
EOF

  sed -i "s|https://ethereum-holesky-rpc.publicnode.com|$RPC_URL|g" docker-compose.yaml
  docker compose up -d

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

# === VERIFY ===
echo -e "\n🔍 Verifying Trap registration..."
OWNER_ADDR=$(cast wallet address --private-key $PRIVATE_KEY)
cast call 0x4608Afa7f277C8E0BE232232265850d1cDeB600E "isResponder(address)(bool)" $OWNER_ADDR --rpc-url $RPC_URL

# === DONE ===
echo -e "\n✅ Setup complete!"
echo "🌐 Go to https://app.drosera.io and connect your wallet"
echo "📦 Use dashboard to opt-in and set Bloom"
echo "🧠 For logs: journalctl -u drosera.service -f  OR  docker logs -f drosera-node"
