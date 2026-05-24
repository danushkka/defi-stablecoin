# 🪙 Decentralized Stablecoin (DSC) — CNY-Pegged Algorithmic Stablecoin
 
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.30-363636?logo=solidity)](https://soliditylang.org/)
[![Built with Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C?logo=ethereum)](https://getfoundry.sh/)
 
A minimal, overcollateralized, algorithmically stable stablecoin pegged to the **Chinese Yuan (CNY)**, backed by exogenous crypto collateral (wETH and wBTC). Inspired by MakerDAO's DAI, but with no governance and no fees.
 
---
 
## 📋 Table of Contents
 
- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Contracts](#contracts)
- [How It Works](#how-it-works)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Environment Setup](#environment-setup)
- [Usage](#usage)
  - [Build](#build)
  - [Test](#test)
  - [Deploy](#deploy)
- [Deployed Contracts](#deployed-contracts)
- [Security Considerations](#security-considerations)
- [Known Issues & Limitations](#known-issues--limitations)
- [License](#license)
---
 
## Overview
 
The **Decentralized Stablecoin (DSC)** system is designed to maintain a **1 DSC = 1 CNY** peg at all times through algorithmic overcollateralization. Users deposit crypto collateral (wETH or wBTC) to mint DSC tokens. The system ensures that the total value of all collateral always exceeds the total value of all minted DSC.
 
> This project is for educational purposes and is based on Patrick Collins' Cyfrin Updraft DeFi course.
 
---
 
## Features
 
- **CNY-Pegged** — Each DSC token targets a value of 1 Chinese Yuan
- **Exogenous Collateral** — Backed by wETH and wBTC (external to the protocol)
- **Overcollateralized** — Minimum 200% collateralization ratio enforced at all times
- **Algorithmic Stability** — No governance; stability maintained entirely by on-chain logic
- **Chainlink Price Feeds** — Real-time, manipulation-resistant price data with stale price protection
- **Dual Currency Display** — Collateral values queryable in both CNY (protocol denomination) and USD (for user convenience)
- **Liquidation Mechanism** — Undercollateralized positions can be liquidated with a 10% bonus incentive for liquidators
- **Reentrancy Protected** — All state-changing functions use OpenZeppelin's `ReentrancyGuard`
---
 
## Architecture
 
```
┌─────────────────────────────────────────────────────────────┐
│                         User                                │
└────────────────────────┬────────────────────────────────────┘
                         │ deposit / mint / burn / redeem
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      DSCEngine.sol                          │
│  - Manages collateral deposits & redemptions                │
│  - Controls DSC minting & burning                           │
│  - Enforces health factor & liquidation logic               │
│  - Reads prices from Chainlink via OracleLib                │
└──────────────┬──────────────────────┬───────────────────────┘
               │ mint / burn          │ price queries
               ▼                      ▼
┌──────────────────────────┐  ┌───────────────────────────────┐
│ DecentralizedStableCoin  │  │   Chainlink Price Feeds       │
│        (DSC ERC-20)      │  │                               │
│  - ERC20Burnable         │  │  ETH/USD ──┐                  │
│  - Ownable (DSCEngine)   │  │  BTC/USD ──┤── collateral     │
└──────────────────────────┘  │  CNY/USD ──┘── peg conversion │
                               └───────────────────────────────┘
```
 
---
 
## Contracts
 
| Contract | Description |
|---|---|
| `DecentralizedStableCoin.sol` | ERC-20 token contract. Minting and burning are restricted to the `DSCEngine` (owner). |
| `DSCEngine.sol` | Core engine. Handles all protocol logic: collateral, minting, redemption, and liquidations. |
| `libraries/OracleLib.sol` | Chainlink oracle wrapper. Adds stale price detection to prevent using outdated price data. |
 
### Key Constants (DSCEngine)
 
| Constant | Value | Description |
|---|---|---|
| `LIQUIDATION_ADJUSTMENT` | 50 | Effective 200% collateralization threshold |
| `LIQUIDATION_PRECISION` | 100 | Divisor for liquidation math |
| `LIQUIDATION_BONUS` | 10 | 10% bonus paid to liquidators |
| `MIN_HEALTH_FACTOR` | 1e18 | Minimum health factor (= 1.0) |
| `ADDITIONAL_FEED_PRECISION` | 1e10 | Scales Chainlink's 8-decimal price to 18 decimals |
 
---
 
## How It Works
 
### Minting DSC
 
1. User calls `depositCollateralAndMintDsc()` (or separately `depositCollateral()` then `mintDsc()`)
2. The engine records the collateral and transfers it to the contract
3. Before minting, the **health factor** is checked:
```
Health Factor = (Collateral Value CNY × 0.5 × 1e18) / DSC Minted
```
 
4. If `Health Factor >= 1e18`, DSC is minted to the user
### Redeeming Collateral
 
1. User calls `redeemCollateralForDsc()` to burn DSC and retrieve collateral atomically, or each step separately
2. Health factor is verified after redemption — if it drops below 1, the transaction reverts
### Liquidation
 
If a user's health factor falls below `1e18` (due to collateral price dropping):
 
1. Any liquidator calls `liquidate(collateral, user, debtToCover)`
2. The liquidator burns `debtToCover` DSC on behalf of the user
3. The liquidator receives the equivalent collateral **+ a 10% bonus**
4. The protocol verifies that the user's health factor actually improved
### CNY Peg Mechanism
 
All internal accounting is denominated in CNY. Collateral USD prices from Chainlink are converted to CNY using the CNY/USD price feed:
 
```
Collateral Value CNY = (Token Amount × Token/USD Price) / (CNY/USD Price)
```
 
USD display functions (`getUsdValue`, `getAccountCollateralValueUsd`) are available as a convenience layer for users but are not used in any protocol logic.
 
---
 
## Getting Started
 
### Prerequisites
 
- [Foundry](https://getfoundry.sh/) — Solidity development toolchain
- [Git](https://git-scm.com/)
Install Foundry if you haven't:
 
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
 
### Installation
 
```bash
git clone https://github.com/your-username/defi-stablecoin.git
cd defi-stablecoin
forge install
```
 
### Environment Setup
 
Create a `.env` file in the root directory:
 
```env
# Sepolia
PRIVATE_KEY=your_private_key_here
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/your_api_key
ETHERSCAN_API_KEY=your_etherscan_api_key
 
# Anvil (local)
ANVIL_RPC_URL=http://localhost:8545
```
 
> ⚠️ Never commit your `.env` file. Make sure it is listed in `.gitignore`.
 
---
 
## Usage
 
### Build
 
```bash
forge build
```
 
### Test
 
```bash
# Run all tests
forge test
 
# Run with verbosity for detailed output
forge test -vvvv
 
# Run a specific test file
forge test --match-path test/unit/DSCEngineTest.t.sol
 
# Run with gas reporting
forge test --gas-report
 
# Run coverage report
forge coverage
 
# Run coverage with lcov output
forge coverage --report lcov
```
 
### Deploy
 
**Local Anvil:**
 
```bash
anvil
forge script script/DeployDSC.s.sol:DeployDSC \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```
 
**Sepolia testnet:**
 
```bash
source .env
forge script script/DeployDSC.s.sol:DeployDSC \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```
 
---
 
## Deployed Contracts
 
### Sepolia Testnet
 
| Contract | Address |
|---|---|
| `DecentralizedStableCoin` | [`0x135c5016C2983E0833498E25ff19f30947130C79`](https://sepolia.etherscan.io/address/0x135c5016C2983E0833498E25ff19f30947130C79) |
| `DSCEngine` | [`0xb01a8F4FDDd802f0bF446BF98e5117807b929fAC`](https://sepolia.etherscan.io/address/0xb01a8F4FDDd802f0bF446BF98e5117807b929fAC) |
 
---
 
## Security Considerations
 
- **Reentrancy** — All external state-changing functions are protected by `nonReentrant` from OpenZeppelin's `ReentrancyGuard`
- **Stale Oracles** — `OracleLib.stalePriceCheck()` reverts if a Chainlink price feed hasn't been updated within the allowed timeout, preventing the protocol from using outdated prices during market disruptions
- **Health Factor Enforcement** — Every mint and collateral withdrawal checks the health factor post-action, ensuring the protocol cannot be left in an undercollateralized state
- **Liquidation Safeguard** — Liquidations require the target user's health factor to actually improve, preventing griefing or broken liquidation calls
---
 
## Known Issues & Limitations
 
- **No governance** — Protocol parameters (collateral ratio, bonus, supported tokens) are hardcoded. Updating them requires redeployment.
- **Centralized minting** — `DecentralizedStableCoin` uses `Ownable`. If the DSCEngine is compromised, all DSC can be minted arbitrarily.
- **CNY/USD oracle dependency** — The peg accuracy depends entirely on the Chainlink CNY/USD feed. If that feed goes stale or is manipulated, the protocol freezes (by design via OracleLib) or misprices collateral.
- **Single collateral liquidation** — Liquidations only seize one collateral type per call. A user with both wETH and wBTC collateral may require multiple liquidation calls.
---
 
## License
 
This project is licensed under the [MIT License](LICENSE).