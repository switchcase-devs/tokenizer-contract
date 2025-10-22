# RealEstateToken

**Contract:** `RealEstateToken`  
**Pattern:** OpenZeppelin v5 Upgradeable (no constructor; use `initialize`)  
**Standards:** ERC-20, EIP-2612 (Permit), ERC20Votes (delegation disabled), Pausable, AccessControlEnumerable  
**Compliance controls:** Freeze, Whitelist/Role-gated modes, Partial balance locks, Evidence-backed `forceTransfer` (operator override)  
**Decimals:** `0` (indivisible units)

---

## 1) Roles & Governance

### Role identifiers
- `ROLE_ADMIN` (`0x00`): superuser; manages role governance and mode toggles
- `ROLE_TRANSFER`: may initiate transfers in role-gated mode; in whitelist mode bypasses whitelist checks for the caller
- `ROLE_MINTER`: allowed to mint
- `ROLE_BURNER`: allowed to call `burnFrom`
- `ROLE_PAUSER`: allowed to `pause` / `unpause`
- `ROLE_WHITELIST`: allowed to manage `setWhitelist`
- `ROLE_TRANSFER_RESTRICT`: allowed to manage `setFrozen`, `lockBalance`, `unlockBalance`

### Role capabilities (matrix)

| Capability / Function                                  | ROLE_ADMIN | ROLE_TRANSFER | ROLE_MINTER | ROLE_BURNER | ROLE_PAUSER | ROLE_WHITELIST | ROLE_TRANSFER_RESTRICT |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Grant/Revoke roles (`grantRole`, `revokeRole`)         | ✅         | ❌            | ❌          | ❌          | ❌          | ❌              | ❌                      |
| Set whitelist mode (`setWhitelistMode`)                | ✅         | ❌            | ❌          | ❌          | ❌          | ❌              | ❌                      |
| Whitelist accounts (`setWhitelist`)                    | ❌         | ❌            | ❌          | ❌          | ❌          | ✅              | ❌                      |
| Freeze/unfreeze (`setFrozen`)                          | ❌         | ❌            | ❌          | ❌          | ❌          | ❌              | ✅                      |
| Lock/unlock balances (`lockBalance`, `unlockBalance`)  | ❌         | ❌            | ❌          | ❌          | ❌          | ❌              | ✅                      |
| Mint (`mint`)                                          | ❌         | ❌            | ✅          | ❌          | ❌          | ❌              | ❌                      |
| Burn via allowance (`burnFrom`)                        | ❌         | ❌            | ❌          | ✅          | ❌          | ❌              | ❌                      |
| Pause/Unpause (`pause`, `unpause`)                     | ❌         | ❌            | ❌          | ❌          | ✅          | ❌              | ❌                      |
| Initiate transfer in **role-gated** mode               | ❌         | ✅            | ❌          | ❌          | ❌          | ❌              | ❌                      |
| Initiate transfer in **whitelist** mode w/o checks     | ❌         | ✅ (caller)   | ❌          | ❌          | ❌          | ❌              | ❌                      |
| Forced transfer (`forceTransfer`)                      | ❌         | ✅            | ❌          | ❌          | ❌          | ❌              | ❌                      |

> **Operator override:** `forceTransfer` bypasses **freeze**, **lock**, and **whitelist** checks; it still requires `ROLE_TRANSFER`, sufficient **balance**, and not being **paused**.

---

## 2) Modes & Compliance Logic

### Modes
- **Role-gated (default):** Only callers with `ROLE_TRANSFER` may initiate `transfer` / `transferFrom`.
- **Whitelist mode:** If the caller lacks `ROLE_TRANSFER`, both `from` and `to` must be whitelisted. Holders of `ROLE_TRANSFER` may transfer regardless of whitelist status.

### Transfer compliance (when `from != 0` and `to != 0`)
- **Freeze:** reverts `AccountFrozen(account)` if `_frozen[from]` or `_frozen[to]` (skipped during `forceTransfer`).
- **Lock:** reverts `LockExceedsUnlocked(from, requested, unlocked)` if `amount > (balanceOf(from) − _locked[from])` (skipped during `forceTransfer`).
- **Whitelist:** if whitelist mode and caller lacks `ROLE_TRANSFER`, both ends must be whitelisted (skipped during `forceTransfer`).
- **Role-gated:** when not in whitelist mode, caller must have `ROLE_TRANSFER` (applies also to `forceTransfer`).
- **Balance:** always enforced — reverts `ERC20InsufficientBalance(from, bal, amount)` if insufficient (applies to `forceTransfer`).
- **Pause:** when paused, any state-changing token op reverts `EnforcedPause()` (applies to `forceTransfer`, mint, burn).

---

## 3) Voting (Delegation-Free)

- Delegation is **fully disabled**:
    - `delegate(address)` → reverts `DelegationDisabled()`
    - `delegateBySig(...)` → reverts `DelegationDisabled()`
    - `delegates(address account)` → always returns `account`
- Voting units move exactly with token units on every transfer.
- **Invariant:** `getVotes(account) == balanceOf(account)` always.

---

## 4) Public / External Interface

> Solidity 0.8.x checked arithmetic. Revert reasons include ERC-6093 errors and the contract’s custom errors.

### Initialization
- `initialize(string name_, string symbol_, uint256 initialSupply_, address admin_)`  
  Sets metadata, grants roles to `admin_`, mints `initialSupply_` to `admin_`, enables role-gated mode by default.

### ERC-20 Metadata
- `name() -> string`, `symbol() -> string`, `decimals() -> uint8` (always `0`)

### ERC-20 Supply / Balances
- `totalSupply() -> uint256`, `balanceOf(address) -> uint256`

### ERC-20 Transfers & Allowances
- `transfer(address to, uint256 amount) -> bool`
- `approve(address spender, uint256 amount) -> bool`
- `allowance(address owner, address spender) -> uint256`
- `transferFrom(address from, address to, uint256 amount) -> bool`

### Mint & Burn
- `mint(address to, uint256 amount)` — **Only `ROLE_MINTER`**, reverts if paused
- `burn(uint256 amount)` — from caller
- `burnFrom(address account, uint256 amount)` — **Only `ROLE_BURNER`**, checks allowance, reverts if paused

### Pausable
- `pause()` / `unpause()` — **Only `ROLE_PAUSER`**
- `paused() -> bool`

### Whitelist / Freeze / Locks
- `setWhitelistMode(bool enabled)` — **Only `ROLE_ADMIN`**
- `setWhitelist(address account, bool status)` — **Only `ROLE_WHITELIST`**
- `setFrozen(address account, bool frozen_)` — **Only `ROLE_TRANSFER_RESTRICT`**
- `lockBalance(address account, uint256 amount)` — **Only `ROLE_TRANSFER_RESTRICT`**
- `unlockBalance(address account, uint256 amount)` — **Only `ROLE_TRANSFER_RESTRICT`**
- `lockedBalanceOf(address) -> uint256`, `isFrozen(address) -> bool`, `isWhitelisted(address) -> bool`

### Forced Transfers (Operator Override)
- `forceTransfer(address from, address to, uint256 amount, bytes data)` — **Only `ROLE_TRANSFER`**  
  Requirements: `from != 0`, `to != 0`, `data.length > 0`  
  Bypasses: freeze, lock, whitelist  
  Still enforced: role requirement, pause, balance  
  Emits: `ForcedTransfer(operator, from, to, amount, data)`

### Permit (EIP-2612)
- `permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)`
- `nonces(address owner) -> uint256`, `DOMAIN_SEPARATOR() -> bytes32`

### Votes (delegation-free profile)
- `getVotes(address account) -> uint256`
- `getPastVotes(address account, uint256 timepoint) -> uint256`
- `getPastTotalSupply(uint256 timepoint) -> uint256`
- `delegates(address account) -> address` (returns `account`)
- `delegate(address)` — reverts
- `delegateBySig(...)` — reverts
- `clock() -> uint48`, `CLOCK_MODE() -> string`

### AccessControlEnumerable
- `hasRole`, `getRoleAdmin`, `grantRole`, `revokeRole`, `renounceRole`, `getRoleMember`, `getRoleMemberCount`

### ERC-165
- `supportsInterface(bytes4 interfaceId) -> bool`

---

## 5) Errors & Events

### Custom errors
- `AccountFrozen(address account)`
- `MissingTransferRole(address operator)`
- `NotWhitelisted(address account)`
- `EmptyForceTransferData()`
- `UnlockExceedsLocked(address account, uint256 requested, uint256 locked)`
- `LockExceedsUnlocked(address account, uint256 requested, uint256 unlocked)`
- `DelegationDisabled()`

### ERC-6093 errors
- `ERC20InvalidSender(address)`
- `ERC20InvalidReceiver(address)`
- `ERC20InsufficientBalance(address,uint256,uint256)`
- `ERC20InsufficientAllowance(address,uint256,uint256)`

### Pausable
- `EnforcedPause()`

### Events
- `AccountFrozenSet(address,bool)`
- `BalanceLocked(address,uint256)`
- `BalanceUnlocked(address,uint256)`
- `Whitelisted(address,bool)`
- `WhitelistModeChanged(bool)`
- `ForcedTransfer(address,address,address,uint256,bytes)`
- Standard ERC-20 / ERC20Votes / AccessControl events.

---

## 6) Non-Ambiguous Behavior Notes

1. **Operator override:** `forceTransfer` bypasses **freeze**, **lock**, and **whitelist**. It still requires `ROLE_TRANSFER`, not paused, and sufficient balance.
2. **Role-gated vs whitelist:** outside `forceTransfer`, `ROLE_TRANSFER` is required in role-gated mode; in whitelist mode callers without `ROLE_TRANSFER` must whitelist both ends.
3. **Locks/freeze management:** only `ROLE_TRANSFER_RESTRICT` can lock/unlock or freeze/unfreeze.
4. **Delegation-free voting:** `getVotes == balanceOf` always.
5. **Decimals:** fixed to `0`.
6. **Upgradeable:** always use `initialize(...)` once; preserve storage layout and `__gap` for upgrades.

---

## 7) Security-Relevant Invariants (recommended tests)

- `locked[a] ≤ balanceOf[a]` always (except during `forceTransfer` bypass — locks aren’t enforced, but balance still is).
- When paused, `transfer`, `forceTransfer`, `mint`, `burnFrom` revert.
- Role-gated: non-`ROLE_TRANSFER` cannot transfer.
- Whitelist mode: non-`ROLE_TRANSFER` requires both parties whitelisted.
- Voting: `getVotes(a) == balanceOf(a)` after any sequence of mint/burn/transfer/forceTransfer.
- `forceTransfer` emits `ForcedTransfer` and bypasses lock/freeze/whitelist while keeping balance and pause semantics.

---

## API Index

### Initialization
- `initialize(string name_, string symbol_, uint256 initialSupply_, address admin_)`

### Metadata
- `name() -> string`
- `symbol() -> string`
- `decimals() -> uint8`

### Supply & Balances
- `totalSupply() -> uint256`
- `balanceOf(address account) -> uint256`

### Transfers & Allowances (ERC-20)
- `transfer(address to, uint256 amount) -> bool`
- `approve(address spender, uint256 amount) -> bool`
- `allowance(address owner, address spender) -> uint256`
- `transferFrom(address from, address to, uint256 amount) -> bool`

### Mint & Burn
- `mint(address to, uint256 amount)`  *(ROLE_MINTER)*
- `burn(uint256 amount)`
- `burnFrom(address account, uint256 amount)`  *(ROLE_BURNER)*

### Pausable
- `pause()`  *(ROLE_PAUSER)*
- `unpause()`  *(ROLE_PAUSER)*
- `paused() -> bool`

### Whitelist / Freeze / Locks
- `setWhitelistMode(bool enabled)`  *(ROLE_ADMIN)*
- `setWhitelist(address account, bool status)`  *(ROLE_WHITELIST)*
- `setFrozen(address account, bool frozen_)`  *(ROLE_TRANSFER_RESTRICT)*
- `lockBalance(address account, uint256 amount)`  *(ROLE_TRANSFER_RESTRICT)*
- `unlockBalance(address account, uint256 amount)`  *(ROLE_TRANSFER_RESTRICT)*
- `lockedBalanceOf(address account) -> uint256`
- `isFrozen(address account) -> bool`
- `isWhitelisted(address account) -> bool`

### Forced Transfers (Operator Override)
- `forceTransfer(address from, address to, uint256 amount, bytes data)`  *(ROLE_TRANSFER)*

### Permit (EIP-2612)
- `permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)`
- `nonces(address owner) -> uint256`
- `DOMAIN_SEPARATOR() -> bytes32`

### Votes (Delegation-Free)
- `getVotes(address account) -> uint256`
- `getPastVotes(address account, uint256 timepoint) -> uint256`
- `getPastTotalSupply(uint256 timepoint) -> uint256`
- `delegates(address account) -> address`  *(returns `account`)*
- `delegate(address)`  *(reverts)*
- `delegateBySig(...)`  *(reverts)*
- `clock() -> uint48`
- `CLOCK_MODE() -> string`

### AccessControl / AccessControlEnumerable
- `hasRole(bytes32 role, address account) -> bool`
- `getRoleAdmin(bytes32 role) -> bytes32`
- `grantRole(bytes32 role, address account)`
- `revokeRole(bytes32 role, address account)`
- `renounceRole(bytes32 role, address callerConfirmation)`
- `getRoleMember(bytes32 role, uint256 index) -> address`
- `getRoleMemberCount(bytes32 role) -> uint256`

### ERC-165
- `supportsInterface(bytes4 interfaceId) -> bool`
