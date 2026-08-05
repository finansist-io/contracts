// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {PersonalVaultV1} from "../../src/PersonalVaultV1.sol";
import {VaultFactoryV1} from "../../src/VaultFactoryV1.sol";
import {TestSetup} from "../helpers/TestSetup.sol";

contract VaultFactoryV1Test is TestSetup {
    function testCloneAddressIsDeterministicAndInitialized() public view {
        address predicted = vaultFactory.predictVault(owner, LINEAGE, MARKET_ID);

        assertEq(predicted, address(vault));
        assertEq(vault.factory(), address(vaultFactory));
        assertEq(vault.owner(), owner);
        assertEq(vault.strategyLineage(), LINEAGE);
        assertEq(vault.marketId(), MARKET_ID);
        assertEq(vault.registry(), address(registry));
        assertEq(vault.entryGuard(), address(guard));
        assertEq(vault.accountingToken(), address(usdc));
        assertEq(vault.targetToken(), address(target));
    }

    function testAnyoneMayCreateButCannotBecomeOwner() public {
        address requestedOwner = makeAddr("requestedOwner");
        bytes32 lineage = keccak256("second-lineage");

        vm.prank(makeAddr("relayer"));
        PersonalVaultV1 created = PersonalVaultV1(vaultFactory.createVault(requestedOwner, lineage, MARKET_ID));

        assertEq(created.owner(), requestedOwner);
        assertEq(created.factory(), address(vaultFactory));
    }

    function testDuplicateVaultIsRejected() public {
        bytes32 key = vaultFactory.vaultKey(owner, LINEAGE, MARKET_ID);
        vm.expectRevert(abi.encodeWithSelector(VaultFactoryV1.VaultAlreadyExists.selector, key, address(vault)));
        vaultFactory.createVault(owner, LINEAGE, MARKET_ID);
    }

    function testImplementationCannotBeInitializedDirectly() public {
        PersonalVaultV1 implementation = PersonalVaultV1(vaultFactory.implementation());
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(owner, LINEAGE, MARKET_ID, address(registry), address(guard));
    }

    function testFactoryRejectsNonContractGuard() public {
        address notAContract = makeAddr("notAContract");
        vm.expectRevert(abi.encodeWithSelector(VaultFactoryV1.InvalidContract.selector, notAContract));
        new VaultFactoryV1(address(registry), notAContract);
    }

    function testFactoryRejectsNonContractRegistry() public {
        address notAContract = makeAddr("notARegistry");
        vm.expectRevert(abi.encodeWithSelector(VaultFactoryV1.InvalidContract.selector, notAContract));
        new VaultFactoryV1(notAContract, address(guard));
    }

    function testCloneRejectsNonContractGuard() public {
        address clone = Clones.clone(vaultFactory.implementation());
        vm.expectRevert(PersonalVaultV1.ZeroAddress.selector);
        PersonalVaultV1(clone).initialize(owner, keccak256("isolated-lineage"), MARKET_ID, address(registry), owner);
    }
}
