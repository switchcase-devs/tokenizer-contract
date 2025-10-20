// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* ───────────────────────────────────────────────────────────────────────────
   RealEstateToken — permissioned ERC-20 for tokenised real-estate shares
   (minor edit: IERC6093 import updated to IERC20Errors for OZ v5 compatibility)
   ───────────────────────────────────────────────────────────────────────── */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/governance/utils/Votes.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";
import "@openzeppelin/contracts/interfaces/IERC20Errors.sol"; // ERC-6093 errors (ERC20InsufficientBalance, etc.)

/**
 * @title RealEstateToken
 * @notice Permissioned ERC-20 with controls, evidence-backed forced transfers,
 *         and vote checkpoints (ERC20Votes). Votes are locked to balances by disabling
 *         third-party delegation and auto self-delegating on first token movement.
 * @dev    Uses OpenZeppelin Contracts v5.x. All non-ERC20 specific reverts use custom errors.
 */
contract RealEstateToken is
    ERC20,
    ERC20Permit,
    ERC20Burnable,
    ERC20Pausable,
    ERC20Votes,
    AccessControlEnumerable
{
    // ─────────────────────────────────────────────────────────────────────
    // Roles
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Global admin role (alias for AccessControl's 0x00).
    bytes32 public constant ROLE_ADMIN     = 0x00;
    /// @notice Operator allowed to move tokens and perform forced transfers.
    bytes32 public constant ROLE_TRANSFER  = keccak256("ROLE_TRANSFER");
    /// @notice Role allowed to mint new supply.
    bytes32 public constant ROLE_MINTER    = keccak256("ROLE_MINTER");
    /// @notice Role allowed to burn via allowance using {burnFrom}.
    bytes32 public constant ROLE_BURNER    = keccak256("ROLE_BURNER");
    /// @notice Role allowed to pause and unpause transfers.
    bytes32 public constant ROLE_PAUSER    = keccak256("ROLE_PAUSER");

    // ─────────────────────────────────────────────────────────────────────
    // Compliance state
    // ─────────────────────────────────────────────────────────────────────

    mapping(address => bool)    private _frozen;       // account-level freeze
    mapping(address => uint256) private _locked;       // non-transferable balance portion
    mapping(address => bool)    private _whitelisted;  // KYC/allow-list flag
    bool public whitelistEnabled;                      // false ⇒ role-gated mode

    // ─────────────────────────────────────────────────────────────────────
    // Errors (custom, gas-efficient)
    // ─────────────────────────────────────────────────────────────────────

    /// @dev Emitted when a transfer party is frozen.
    error AccountFrozen(address account);
    /// @dev Sender lacks the transfer role while whitelist mode is disabled.
    error MissingTransferRole(address operator);
    /// @dev Party is not whitelisted but whitelist mode is enabled.
    error NotWhitelisted(address account);
    /// @dev Evidence payload for {forceTransfer} is empty.
    error EmptyForceTransferData();
    /// @dev Attempted unlock exceeds the currently locked amount.
    error UnlockExceedsLocked(address account, uint256 requested, uint256 locked);
    /// @dev Requested lock exceeds unlocked balance.
    error LockExceedsUnlocked(address account, uint256 requested, uint256 unlocked);
    /// @dev Voting power delegation to a 3rd-party is disabled.
    error DelegationDisabled();

    // ─────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Emitted when an account is frozen by admin.
    event AccountFrozenSet(address indexed account, bool frozen);
    /// @notice Emitted when a portion of an account balance is locked.
    event BalanceLocked(address indexed account, uint256 amount);
    /// @notice Emitted when a portion of an account's locked balance is unlocked.
    event BalanceUnlocked(address indexed account, uint256 amount);
    /// @notice Emitted when an account's whitelist status changes.
    event Whitelisted(address indexed account, bool status);
    /// @notice Emitted when the whitelist/role-gated mode is toggled.
    event WhitelistModeChanged(bool enabled);
    /// @notice Emitted for an operator override transfer with evidence bytes.
    event ForcedTransfer(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes   data
    );

    // ─────────────────────────────────────────────────────────────────────
    // Construction
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @notice Initializes the token and boots roles.
     * @param name_          Token name (also used for ERC20Permit domain).
     * @param symbol_        Token symbol.
     * @param initialSupply_ Initial supply minted to `admin_`.
     * @param admin_         Address receiving admin and operational roles.
     */
    constructor(
        string  memory name_,
        string  memory symbol_,
        uint256 initialSupply_,
        address admin_
    )
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        _grantRole(ROLE_ADMIN,    admin_);
        _grantRole(ROLE_MINTER,   admin_);
        _grantRole(ROLE_BURNER,   admin_);
        _grantRole(ROLE_TRANSFER, admin_);
        _grantRole(ROLE_PAUSER,   admin_);

        _mint(admin_, initialSupply_);
        whitelistEnabled = false; // start in strict, role-gated mode
    }

    // ─────────────────────────────────────────────────────────────────────
    // ERC-20 metadata
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns the number of decimals used for user representation.
     * @dev    Overridden to 0 to represent indivisible units (e.g., shares).
     */
    function decimals() public view virtual override returns (uint8) {
        return 0;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Admin: whitelist & mode
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @notice Enables/disables whitelist mode.
     * @dev    When enabled: transfers by non-operators require both parties whitelisted.
     * @param enabled `true` to enable whitelist mode, `false` to require ROLE_TRANSFER.
     */
    function setWhitelistMode(bool enabled)
        external
        onlyRole(ROLE_ADMIN)
    {
        whitelistEnabled = enabled;
        emit WhitelistModeChanged(enabled);
    }

    /**
     * @notice Sets allow-list status for `account`.
     * @param account Address to update.
     * @param status  `true` to whitelist, `false` to remove.
     */
    function setWhitelist(address account, bool status)
        external
        onlyRole(ROLE_ADMIN)
    {
        _whitelisted[account] = status;
        emit Whitelisted(account, status);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Admin: pause / freeze / lock
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @notice Pauses all token transfers.
     * @dev    See {ERC20Pausable}.
     */
    function pause() external onlyRole(ROLE_PAUSER) { _pause(); }

    /**
     * @notice Unpauses token transfers.
     * @dev    See {ERC20Pausable}.
     */
    function unpause() external onlyRole(ROLE_PAUSER) { _unpause(); }

    /**
     * @notice Freezes or unfreezes an account.
     * @param account Account to update.
     * @param frozen_ `true` to freeze, `false` to unfreeze.
     */
    function setFrozen(address account, bool frozen_)
        external
        onlyRole(ROLE_ADMIN)
    {
        _frozen[account] = frozen_;
        emit AccountFrozenSet(account, frozen_);
    }

    /**
     * @notice Locks `amount` of `account`'s balance, making it non-transferable.
     * @param account Address whose balance will be locked.
     * @param amount  Amount to lock.
     * @dev    Reverts with {LockExceedsUnlocked} if `amount` > unlocked balance.
     */
    function lockBalance(address account, uint256 amount)
        external
        onlyRole(ROLE_ADMIN)
    {
        uint256 bal = balanceOf(account);
        uint256 unlocked = bal - _locked[account];
        if (amount == 0 || amount > unlocked) {
            revert LockExceedsUnlocked(account, amount, unlocked);
        }
        _locked[account] += amount;
        emit BalanceLocked(account, amount);
    }

    /**
     * @notice Unlocks `amount` previously locked for `account`.
     * @param account Address whose locked balance will be reduced.
     * @param amount  Amount to unlock.
     * @dev    Reverts with {UnlockExceedsLocked} if `amount` > currently locked.
     */
    function unlockBalance(address account, uint256 amount)
        external
        onlyRole(ROLE_ADMIN)
    {
        uint256 locked = _locked[account];
        if (amount == 0 || amount > locked) {
            revert UnlockExceedsLocked(account, amount, locked);
        }
        _locked[account] = locked - amount;
        emit BalanceUnlocked(account, amount);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Mint / Burn
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @notice Mints `amount` tokens to `to`.
     * @param to     Recipient address.
     * @param amount Amount to mint.
     * @dev    Restricted to {ROLE_MINTER}.
     */
    function mint(address to, uint256 amount)
        external
        onlyRole(ROLE_MINTER)
    {
        _mint(to, amount);
    }

    /**
     * @notice Burns `amount` tokens from `account` using allowance.
     * @param account Owner whose allowance is used.
     * @param amount  Amount to burn.
     * @dev    Restricted to {ROLE_BURNER}. Will revert with ERC-6093 errors
     *         from {_spendAllowance} if allowance is insufficient.
     */
    function burnFrom(address account, uint256 amount)
        public
        override(ERC20Burnable)
        onlyRole(ROLE_BURNER)
    {
        _spendAllowance(account, _msgSender(), amount); // may revert with ERC20InsufficientAllowance
        _burn(account, amount);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Forced transfers (with evidence)
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @notice Operator override transfer tied to an evidence payload.
     * @param from   Source account (cannot be the zero address).
     * @param to     Destination account (cannot be the zero address).
     * @param amount Tokens to move.
     * @param data   Arbitrary evidence payload (e.g., court-order hash/JSON).
     * @dev    Restricted to {ROLE_TRANSFER}. Emits {ForcedTransfer}.
     *         Will revert with ERC-6093 errors for invalid sender/receiver.
     */
    function forceTransfer(
        address from,
        address to,
        uint256 amount,
        bytes calldata data
    )
        external
        onlyRole(ROLE_TRANSFER)
    {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to   == address(0)) revert ERC20InvalidReceiver(address(0));
        if (data.length == 0)   revert EmptyForceTransferData();

        _transfer(from, to, amount); // triggers compliance in {_update}
        emit ForcedTransfer(_msgSender(), from, to, amount, data);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Delegation (disabled) — votes == balances
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @notice Delegation is restricted to self-delegation.
     * @param delegatee Must equal `msg.sender`.
     * @dev    A first-time self-delegation creates the initial checkpoint.
     */
    function delegate(address delegatee)
        public
        override(Votes)
    {
        if (delegatee != _msgSender()) revert DelegationDisabled();
        super.delegate(delegatee);
    }

    /**
     * @notice Off-chain signed delegation is disabled.
     * @dev    Always reverts to keep votes equal to current balances.
     */
    function delegateBySig(
        address, uint256, uint256,
        uint8, bytes32, bytes32
    )
        public
        pure
        override(Votes)
    {
        revert DelegationDisabled();
    }

    // ─────────────────────────────────────────────────────────────────────
    // Transfer hook & compliance (v5 uses _update)
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @dev Central transfer hook. Enforces pause, freeze, whitelist/role gating,
     *      and locked-balance logic. Auto self-delegates parties on first movement
     *      so that voting power always tracks balances.
     */
    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Pausable, ERC20Votes)
    {
        // Ensure votes tracking is active for parties touching tokens
        if (from != address(0) && delegates(from) == address(0)) {
            _delegate(from, from);
        }
        if (to != address(0) && delegates(to) == address(0)) {
            _delegate(to, to);
        }

        if (from != address(0) && to != address(0)) {
            // Frozen checks
            if (_frozen[from]) revert AccountFrozen(from);
            if (_frozen[to])   revert AccountFrozen(to);

            // Balance then locked-balance checks (ERC-6093 where applicable)
            uint256 fromBal = balanceOf(from);
            if (fromBal < amount) {
                revert ERC20InsufficientBalance(from, fromBal, amount);
            }
            uint256 unlocked = fromBal - _locked[from];
            if (amount > unlocked) {
                revert LockExceedsUnlocked(from, amount, unlocked);
            }

            // Mode gating: whitelist vs ROLE_TRANSFER
            if (whitelistEnabled) {
                if (!hasRole(ROLE_TRANSFER, _msgSender())) {
                    if (!_whitelisted[from]) revert NotWhitelisted(from);
                    if (!_whitelisted[to])   revert NotWhitelisted(to);
                }
            } else {
                if (!hasRole(ROLE_TRANSFER, _msgSender())) {
                    revert MissingTransferRole(_msgSender());
                }
            }
        }

        super._update(from, to, amount); // pause & votes bookkeeping
    }

    // ─────────────────────────────────────────────────────────────────────
    // ERC-2612 / Nonces diamond
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @inheritdoc ERC20Permit
     * @dev Disambiguates the multiple inheritance of {nonces}.
     */
    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Returns the amount currently locked for `account`.
    function lockedBalanceOf(address account) external view returns (uint256) {
        return _locked[account];
    }

    /// @notice Returns `true` if `account` is frozen.
    function isFrozen(address account) external view returns (bool) {
        return _frozen[account];
    }

    /// @notice Returns `true` if `account` is whitelisted.
    function isWhitelisted(address account) external view returns (bool) {
        return _whitelisted[account];
    }

    // ─────────────────────────────────────────────────────────────────────
    // ERC-165
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @inheritdoc AccessControlEnumerable
     */
    function supportsInterface(bytes4 id)
        public
        view
        override(AccessControlEnumerable)
        returns (bool)
    {
        return super.supportsInterface(id);
    }
}
