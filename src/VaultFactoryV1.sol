// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PersonalVaultV1} from "./PersonalVaultV1.sol";

contract VaultFactoryV1 is ReentrancyGuard {
    error ZeroAddress();
    error InvalidContract(address target);
    error InvalidLineage();
    error VaultAlreadyExists(bytes32 vaultKey, address vault);

    bytes32 public constant VAULT_VERSION = keccak256("FINANSIST_PERSONAL_VAULT_V1");

    address private immutable _implementation;
    address private immutable _registry;
    address private immutable _entryGuard;

    mapping(bytes32 vaultKey => address vault) public vaultForKey;

    event VaultCreated(
        bytes32 indexed vaultKey,
        address indexed vault,
        address indexed owner,
        bytes32 strategyLineage,
        bytes32 marketId
    );

    constructor(address registry_, address entryGuard_) {
        if (registry_ == address(0) || entryGuard_ == address(0)) revert ZeroAddress();
        if (registry_.code.length == 0) revert InvalidContract(registry_);
        if (entryGuard_.code.length == 0) revert InvalidContract(entryGuard_);
        _registry = registry_;
        _entryGuard = entryGuard_;
        _implementation = address(new PersonalVaultV1());
    }

    function createVault(address owner, bytes32 strategyLineage, bytes32 marketId)
        external
        nonReentrant
        returns (address vault)
    {
        if (owner == address(0)) revert ZeroAddress();
        if (strategyLineage == bytes32(0)) revert InvalidLineage();

        bytes32 key = vaultKey(owner, strategyLineage, marketId);
        address existing = vaultForKey[key];
        if (existing != address(0)) revert VaultAlreadyExists(key, existing);

        vault = Clones.cloneDeterministic(_implementation, key);
        vaultForKey[key] = vault;
        PersonalVaultV1(vault).initialize(owner, strategyLineage, marketId, _registry, _entryGuard);
        emit VaultCreated(key, vault, owner, strategyLineage, marketId);
    }

    function predictVault(address owner, bytes32 strategyLineage, bytes32 marketId) external view returns (address) {
        return
            Clones.predictDeterministicAddress(
                _implementation, vaultKey(owner, strategyLineage, marketId), address(this)
            );
    }

    function implementation() external view returns (address) {
        return _implementation;
    }

    function registry() external view returns (address) {
        return _registry;
    }

    function entryGuard() external view returns (address) {
        return _entryGuard;
    }

    function vaultKey(address owner, bytes32 strategyLineage, bytes32 marketId) public view returns (bytes32) {
        // Clarity matters more than replacing this one-time hash with hand-written assembly.
        // forge-lint: disable-next-line(asm-keccak256)
        return keccak256(abi.encode(block.chainid, address(this), VAULT_VERSION, owner, strategyLineage, marketId));
    }
}
