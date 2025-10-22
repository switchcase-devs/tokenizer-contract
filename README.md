# RealEstateToken — Foundry project (tests + invariants + fuzz)

This repository packages your `RealEstateToken` contract with a **complete Foundry test suite**:
- Unit tests (pause/freeze/lock/whitelist/roles/forceTransfer, delegation, burnFrom, interfaces)
- Fuzz tests (transfer vs. locked balance)
- Invariant checks (locked <= balance; votes == balances once self-delegated)

> **Note:** The contract targets **OpenZeppelin Contracts v5.x**. I updated the import
> `interfaces/draft-IERC6093.sol` → `interfaces/IERC20Errors.sol` to align with OZ v5.

## Prerequisites
- Install Foundry: https://book.getfoundry.sh/getting-started/installation

## Setup
```bash
# from the repo root
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2
forge install foundry-rs/forge-std
```

## Run
```bash
forge build
forge test -vvv --gas-report
# Only invariants:
forge test --match-path test/invariants/*
# Only fuzz tests:
forge test --match-path test/fuzz/*
```

## Coverage
Foundry includes experimental coverage. You can try:
```bash
forge coverage
```

## License
MIT
