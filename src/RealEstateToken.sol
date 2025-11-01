// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { ERC20BurnableUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import { ERC20PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import { ERC20VotesUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import { VotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { NoncesUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract RealEstateToken is
Initializable,
ERC20Upgradeable,
ERC20PermitUpgradeable,
ERC20BurnableUpgradeable,
ERC20PausableUpgradeable,
ERC20VotesUpgradeable,
AccessControlEnumerableUpgradeable
{
    bytes32 public constant ROLE_ADMIN                = 0x00;
    bytes32 public constant ROLE_TRANSFER             = keccak256("ROLE_TRANSFER");
    bytes32 public constant ROLE_MINTER               = keccak256("ROLE_MINTER");
    bytes32 public constant ROLE_BURNER               = keccak256("ROLE_BURNER");
    bytes32 public constant ROLE_PAUSER               = keccak256("ROLE_PAUSER");
    bytes32 public constant ROLE_WHITELIST            = keccak256("ROLE_WHITELIST");
    bytes32 public constant ROLE_TRANSFER_RESTRICT    = keccak256("ROLE_TRANSFER_RESTRICT");

    mapping(address => bool)    private _frozen;
    mapping(address => uint256) private _locked;
    mapping(address => bool)    private _whitelisted;
    bool public whitelistEnabled;

    bool private _forceBypass;

    error AccountFrozen(address account);
    error MissingTransferRole(address operator);
    error NotWhitelisted(address account);
    error EmptyForceTransferData();
    error UnlockExceedsLocked(address account, uint256 requested, uint256 locked);
    error LockExceedsUnlocked(address account, uint256 requested, uint256 unlocked);
    error DelegationDisabled();

    event AccountFrozenSet(address indexed account, bool frozen);
    event BalanceLocked(address indexed account, uint256 amount);
    event BalanceUnlocked(address indexed account, uint256 amount);
    event Whitelisted(address indexed account, bool status);
    event WhitelistModeChanged(bool enabled);
    event ForcedTransfer(address indexed operator, address indexed from, address indexed to, uint256 amount, bytes data);

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        address admin_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __ERC20Votes_init();
        __AccessControlEnumerable_init();

        _grantRole(ROLE_ADMIN,             admin_);
        _grantRole(ROLE_MINTER,            admin_);
        _grantRole(ROLE_BURNER,            admin_);
        _grantRole(ROLE_TRANSFER,          admin_);
        _grantRole(ROLE_PAUSER,            admin_);
        _grantRole(ROLE_WHITELIST,         admin_);
        _grantRole(ROLE_TRANSFER_RESTRICT, admin_);

        _mint(admin_, initialSupply_);
        whitelistEnabled = false;
    }

    function decimals() public view virtual override returns (uint8) { return 0; }

    function setWhitelistMode(bool enabled) external onlyRole(ROLE_ADMIN) {
        whitelistEnabled = enabled;
        emit WhitelistModeChanged(enabled);
    }

    function setWhitelist(address account, bool status) external onlyRole(ROLE_WHITELIST) {
        _whitelisted[account] = status;
        emit Whitelisted(account, status);
    }

    function pause() external onlyRole(ROLE_PAUSER) { _pause(); }
    function unpause() external onlyRole(ROLE_PAUSER) { _unpause(); }

    function setFrozen(address account, bool frozen_) external onlyRole(ROLE_TRANSFER_RESTRICT) {
        _frozen[account] = frozen_;
        emit AccountFrozenSet(account, frozen_);
    }

    function lockBalance(address account, uint256 amount) external onlyRole(ROLE_TRANSFER_RESTRICT) {
        uint256 bal = balanceOf(account);
        uint256 unlocked = bal - _locked[account];
        if (amount == 0 || amount > unlocked) revert LockExceedsUnlocked(account, amount, unlocked);
        _locked[account] += amount;
        emit BalanceLocked(account, amount);
    }

    function unlockBalance(address account, uint256 amount) external onlyRole(ROLE_TRANSFER_RESTRICT) {
        uint256 locked = _locked[account];
        if (amount == 0 || amount > locked) revert UnlockExceedsLocked(account, amount, locked);
        _locked[account] = locked - amount;
        emit BalanceUnlocked(account, amount);
    }

    function mint(address to, uint256 amount) external onlyRole(ROLE_MINTER) { _mint(to, amount); }

    function burnFrom(address account, uint256 amount)
    public
    override(ERC20BurnableUpgradeable)
    onlyRole(ROLE_BURNER)
    {
        _burn(account, amount);
    }

    function forceTransfer(address from, address to, uint256 amount, bytes calldata data)
    external
    onlyRole(ROLE_TRANSFER)
    {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to   == address(0)) revert ERC20InvalidReceiver(address(0));
        if (data.length == 0)   revert EmptyForceTransferData();

        _forceBypass = true;
        _transfer(from, to, amount);
        _forceBypass = false;

        emit ForcedTransfer(_msgSender(), from, to, amount, data);
    }

    function delegate(address) public pure override(VotesUpgradeable) {
        revert DelegationDisabled();
    }

    function delegateBySig(
        address, uint256, uint256,
        uint8, bytes32, bytes32
    ) public pure override(VotesUpgradeable) {
        revert DelegationDisabled();
    }

    function delegates(address account) public pure override(VotesUpgradeable) returns (address) {
        return account;
    }

    function _transferVotingUnits(address from, address to, uint256 amount)
    internal
    override(VotesUpgradeable)
    {
        super._transferVotingUnits(from, to, amount);
    }

    function _update(address from, address to, uint256 amount)
    internal
    override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20VotesUpgradeable)
    {
        if (from != address(0) && to != address(0)) {
            if (!_forceBypass) {
                if (_frozen[from]) revert AccountFrozen(from);
                if (_frozen[to])   revert AccountFrozen(to);

                uint256 fromBal = balanceOf(from);
                if (fromBal < amount) revert ERC20InsufficientBalance(from, fromBal, amount);
                uint256 unlocked = fromBal - _locked[from];
                if (amount > unlocked) revert LockExceedsUnlocked(from, amount, unlocked);
            } else {
                uint256 fromBal2 = balanceOf(from);
                if (fromBal2 < amount) revert ERC20InsufficientBalance(from, fromBal2, amount);
            }

            if (whitelistEnabled && !_forceBypass) {
                if (!hasRole(ROLE_TRANSFER, _msgSender())) {
                    if (!_whitelisted[from]) revert NotWhitelisted(from);
                    if (!_whitelisted[to])   revert NotWhitelisted(to);
                }
            } else if (!whitelistEnabled) {
                if (!hasRole(ROLE_TRANSFER, _msgSender())) {
                    revert MissingTransferRole(_msgSender());
                }
            }
        }
        super._update(from, to, amount);
    }

    function nonces(address owner)
    public
    view
    override(ERC20PermitUpgradeable, NoncesUpgradeable)
    returns (uint256)
    { return super.nonces(owner); }

    function lockedBalanceOf(address account) external view returns (uint256) { return _locked[account]; }
    function isFrozen(address account) external view returns (bool) { return _frozen[account]; }
    function isWhitelisted(address account) external view returns (bool) { return _whitelisted[account]; }

    function supportsInterface(bytes4 id)
    public
    view
    override(AccessControlEnumerableUpgradeable)
    returns (bool)
    { return super.supportsInterface(id); }

    uint256[48] private __gap;
}