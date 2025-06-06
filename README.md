# 🚀 Drosera Auto Setup (Trap + Operator)

Fully automated one-click script to deploy a custom **Drosera Trap** and register an **Operator node** using either **Docker** or **SystemD** — with Discord ID included in the response logic.

> Built by [@admirkhen](https://twitter.com/admirkhen) 🧠

---

## 🔧 Features

- Validates your Trap EVM private key and RPC URL
- Builds a custom `Trap.sol` contract that includes your Discord username
- Deploys the trap using `drosera CLI` and `forge`
- Installs & registers the Drosera operator
- Supports **Docker** or **SystemD** install modes
- Configures firewall (UFW) for P2P networking
- Works on Ubuntu VPS (x86_64 or ARM64)

---

## ⚙️ Requirements

- Ubuntu VPS (20.04 or later)
- Root access (`sudo`)
- Public IP address
- EVM private key (64 hex chars)
- Holesky RPC URL (Alchemy, QuickNode, etc.)
- GitHub account
- Discord ID (e.g. `admirkhen#1234`)

---

## 🚀 How to Use

```bash
bash <(curl -s https://raw.githubusercontent.com/emmogrin/Drosera-auto/main/drosera-auto.sh)
