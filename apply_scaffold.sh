#!/usr/bin/env bash
set -euo pipefail

BRANCH="chore/reorg/production-ready"
COMMIT_MSG="chore: add production-ready scaffolding (docs, backend, contracts, sdk, CI, license, readme)"

echo "Creating branch ${BRANCH} (if exists, will switch to it)..."
git checkout -b "${BRANCH}" || git checkout "${BRANCH}"

echo "Creating directories..."
mkdir -p backend/src backend/src/routes contracts/evm/contracts sdk/typescript/src .github/workflows docs

echo "Writing README.md..."
cat > README.md <<'EOF'
# Locust Protocol / Launch Protocol

Monorepo for Locust Protocol — a multi-chain token creation, treasury-backed liquidity, and automation platform.

Workspaces
- frontend/ — Next.js app (UI)
- backend/ — Node.js backend (automation engine, APIs, relayers)
- contracts/evm/ — EVM smart contracts (Hardhat)
- sdk/typescript/ — TypeScript SDK
- docs/ — product & technical documentation

Quickstart (npm)
1. Copy .env.example to .env and configure secrets.
2. Install root dependencies: npm ci
3. Run dev: npm run dev
4. Build: npm run build

Notes
- Admin private keys MUST be stored in a secrets manager (GitHub Secrets / Vault) — do NOT commit private keys to Git.
- This branch contains production-focused scaffolding. No deletions will be performed until you explicitly approve them.
EOF

echo "Writing LICENSE..."
cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2025 dylangoble0-dotcom

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

echo "Writing .env.example..."
cat > .env.example <<'EOF'
# Root environment example (DO NOT commit secrets)
NODE_ENV=development
PORT=4000

# Admin wallet (DO NOT commit private keys)
ADMIN_WALLET_ADDRESS=
# Use a secrets manager (GitHub Secrets) for ADMIN_WALLET_PRIVATE_KEY

# RPC endpoints
ETHEREUM_RPC_URL=
POLYGON_RPC_URL=
SOLANA_RPC_URL=

# Third-party APIs
COINGECKO_API_KEY=
INFURA_PROJECT_ID=
EOF

echo "Writing GitHub Actions CI workflow..."
cat > .github/workflows/ci.yml <<'EOF'
name: CI

on:
  push:
    branches: [ main, master, chore/reorg/production-ready ]
  pull_request:
    branches: [ main, master ]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [18.x]
    steps:
      - uses: actions/checkout@v4
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
          cache: 'npm'
      - name: Install
        run: npm ci
      - name: Build
        run: npm run build --if-present
      - name: Test
        run: npm run test --if-present
EOF

echo "Writing backend package.json and tsconfig..."
cat > backend/package.json <<'EOF'
{
  "name": "@locust/backend",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "ts-node-dev --respawn src/index.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/index.js",
    "test": "jest --passWithNoTests"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ethers": "^6.0.0",
    "axios": "^1.4.0",
    "dotenv": "^16.0.0",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.2.0",
    "jest": "^29.0.0",
    "@types/express": "^4.17.0",
    "@types/uuid": "^9.0.0"
  }
}
EOF

cat > backend/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  }
}
EOF

echo "Writing backend source files..."
cat > backend/src/index.ts <<'EOF'
import express from "express";
import dotenv from "dotenv";
import bodyParser from "body-parser";
import { registerVaultRoutes } from "./routes/vaults";

dotenv.config();

const app = express();
app.use(bodyParser.json());

app.get("/", (req, res) => res.send("Locust Protocol backend"));

app.use("/v1/vaults", registerVaultRoutes());

const port = process.env.PORT || 4000;
app.listen(port, () => {
  console.log(`Backend listening on ${port}`);
});
EOF

cat > backend/src/routes/vaults.ts <<'EOF'
import { Router } from "express";
import * as treasury from "../services/treasury";

export function registerVaultRoutes() {
  const router = Router();

  // Create vault
  router.post("/", (req, res) => {
    try {
      const { owner, thresholdsUSD } = req.body;
      if (!owner || typeof thresholdsUSD !== "number") {
        return res.status(400).json({ error: "owner and thresholdsUSD required" });
      }
      const v = treasury.createVault(owner, thresholdsUSD);
      return res.status(201).json(v);
    } catch (err: any) {
      return res.status(500).json({ error: err.message });
    }
  });

  // List vaults
  router.get("/", (req, res) => {
    return res.json(treasury.listVaults());
  });

  // Get vault
  router.get("/:id", (req, res) => {
    const v = treasury.getVault(req.params.id);
    if (!v) return res.status(404).json({ error: "Vault not found" });
    return res.json(v);
  });

  // Add reward address
  router.post("/:id/reward-address", (req, res) => {
    try {
      const { address } = req.body;
      if (!address) return res.status(400).json({ error: "address required" });
      const v = treasury.addRewardAddress(req.params.id, address);
      return res.json(v);
    } catch (err: any) {
      return res.status(500).json({ error: err.message });
    }
  });

  return router;
}
EOF

cat > backend/src/services/treasury.ts <<'EOF'
import axios from "axios";
import { v4 as uuidv4 } from "uuid";

export type Vault = {
  id: string;
  owner: string;
  thresholdsUSD: number;
  assets: Record<string, number>;
  rewardAddresses: string[];
};

// In-memory map (replace with database in production)
const vaults = new Map<string, Vault>();

const PRICE_API = "https://api.coingecko.com/api/v3/simple/price";

/** Create a vault */
export function createVault(owner: string, thresholdsUSD: number): Vault {
  const id = uuidv4();
  const v: Vault = { id, owner, thresholdsUSD, assets: {}, rewardAddresses: [] };
  vaults.set(id, v);
  return v;
}

/** Register a reward address */
export function addRewardAddress(vaultId: string, addr: string) {
  const v = vaults.get(vaultId);
  if (!v) throw new Error("Vault not found");
  v.rewardAddresses.push(addr);
  return v;
}

/** Compute USD value of vault based on priceMap (symbol => price) */
export function computeVaultUsdValue(vault: Vault, priceMap: Record<string, number>) {
  let total = 0;
  for (const [symbol, amount] of Object.entries(vault.assets)) {
    const price = priceMap[symbol] ?? 0;
    total += amount * price;
  }
  return total;
}

/** Fetch token price from CoinGecko by id (e.g., 'ethereum') */
export async function priceInUsd(id: string): Promise<number> {
  const res = await axios.get(PRICE_API, { params: { ids: id, vs_currencies: "usd" } });
  return res.data?.[id]?.usd || 0;
}

export function getVault(vaultId: string) {
  return vaults.get(vaultId);
}

export function listVaults() {
  return Array.from(vaults.values());
}
EOF

echo "Writing contracts/evm package.json, hardhat config, and contracts..."
cat > contracts/evm/package.json <<'EOF'
{
  "name": "@locust/contracts-evm",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "build": "hardhat compile",
    "test": "hardhat test"
  },
  "devDependencies": {
    "hardhat": "^2.17.0",
    "@nomicfoundation/hardhat-toolbox": "^2.0.0",
    "@openzeppelin/contracts": "^4.9.0"
  }
}
EOF

cat > contracts/evm/hardhat.config.js <<'EOF'
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: "0.8.18",
};
EOF

cat > contracts/evm/contracts/TokenFactory.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/*
  Minimal TokenFactory:
  - deploys a simple ERC20
  - emits TokenCreated
  Production: add access control, minting policies, anti-MEV measures.
*/
contract SimpleToken is ERC20 {
    constructor(string memory name_, string memory symbol_, uint256 initialSupply) ERC20(name_, symbol_) {
        _mint(msg.sender, initialSupply);
    }
}

contract TokenFactory {
    event TokenCreated(address indexed creator, address token);

    function createToken(string calldata name_, string calldata symbol_, uint256 initialSupply) external returns (address) {
        SimpleToken token = new SimpleToken(name_, symbol_, initialSupply);
        emit TokenCreated(msg.sender, address(token));
        return address(token);
    }
}
EOF

cat > contracts/evm/contracts/TreasuryVault.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/*
  Minimal single-token vault skeleton for dev/testing.
  Production: support multi-token accounting, reward-address registration,
  governance, timelock, and secure on-chain swap integrators (oracles + relayer).
*/
contract TreasuryVault is Ownable {
    mapping(address => uint256) public balances;
    address public token;

    event Deposit(address indexed from, uint256 amount);

    constructor(address _token) {
        token = _token;
        transferOwnership(msg.sender);
    }

    function deposit(uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        emit Deposit(msg.sender, amount);
    }
}
EOF

echo "Writing SDK package.json and minimal index..."
cat > sdk/typescript/package.json <<'EOF'
{
  "name": "@locust/sdk",
  "version": "0.1.0",
  "private": true,
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "scripts": {
    "build": "tsc -p tsconfig.json"
  }
}
EOF

cat > sdk/typescript/src/index.ts <<'EOF'
export async function createVault(apiUrl: string, owner: string, thresholdsUSD: number) {
  const res = await fetch(`${apiUrl}/v1/vaults`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ owner, thresholdsUSD }),
  });
  return res.json();
}
EOF

echo "Writing docs/launch_protocol_doc.md (shortened introduction, full spec should be copied from your docs)..."
cat > docs/launch_protocol_doc.md <<'EOF'
TABLE OF CONTENTS
	1.	Executive Summary
	2.	Platform Overview
	3.	Core Vision & Value Proposition
	4.	Target Users & Market Opportunity
	5.	Feature Overview
	6.	System Architecture – Multi-Chain Design
	7.	Smart Contract Architecture – All Chains
	8.	Treasury & Reward Aggregation System
	9.	Automation Engine
	10.	LP Management System (Uniswap, Raydium, OpenBook)
	11.	Token Creation Engine (EVM, Solana, Bitcoin)
	12.	User Flow – From Zero to Launch
	13.	Security & Compliance Strategy
	14.	Business Model & Monetization
	15.	Pricing Strategy
	16.	Competitive Advantage
	17.	Roadmap (18 Months)
	18.	Investor Pitch Outline
	19.	Brand Identity + Naming Concepts

(Full technical specification — please replace or expand with your existing doc content where needed)
EOF

echo "Staging files..."
git add README.md LICENSE .env.example .github backend contracts sdk docs

echo "Committing..."
git commit -m "${COMMIT_MSG}"

echo "Pushing branch to origin..."
git push --set-upstream origin "${BRANCH}"

echo "Done. Files added, branch pushed: ${BRANCH}"
echo "Please open a PR from ${BRANCH} -> main (or master). Paste the PR link here for review."
