// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {GetSender} from "./shared/GetSender.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TWALHook} from "../src/TWALHook.sol";
import {TruncatedOracleImplementation} from "./shared/implementation/TruncatedOracleImplementation.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {TestERC20} from "v4-core/src/test/TestERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";



contract TestTruncatedOracle is Test, Deployers {
    int24 constant MAX_TICK_SPACING = 32767;
    uint160 constant SQRT_RATIO_1_1 = 79228162514264337593543950336;
    uint160 constant SQRT_RATIO_2_1 = 112045541949572279837463876454;

    TestERC20 token0;
    TestERC20 token1;
    PoolManager manager;
    TruncatedOracleImplementation truncatedOracle = TruncatedOracleImplementation(
        address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG
                    | Hooks.BEFORE_SWAP_FLAG
            )
        )
    );
    PoolKey key;
    bytes32 id;

    PoolModifyPositionTest modifyPositionRouter;

    function setUp() public {
        token0 = new TestERC20(2**128);
        token1 = new TestERC20(2**128);
        manager = new PoolManager(500000);

        vm.record();
        TruncatedOracleImplementation impl = new TruncatedOracleImplementation(manager, truncatedOracle);
        (, bytes32[] memory writes) = vm.accesses(address(impl));
        vm.etch(address(truncatedOracle), address(impl).code);
        // for each storage key that was written during the hook implementation, copy the value over
        unchecked {
            for (uint256 i = 0; i < writes.length; i++) {
                bytes32 slot = writes[i];
                vm.store(address(truncatedOracle), slot, vm.load(address(impl), slot));
            }
        }
        truncatedOracle.setTime(1);
        key = PoolKey(
            Currency.wrap(address(token0)), Currency.wrap(address(token1)), 0, MAX_TICK_SPACING, truncatedOracle
        );
        id = PoolId.toId(key);

        modifyPositionRouter = new PoolModifyPositionTest(manager);

        token0.approve(address(truncatedOracle), type(uint256).max);
        token1.approve(address(truncatedOracle), type(uint256).max);
        token0.approve(address(modifyPositionRouter), type(uint256).max);
        token1.approve(address(modifyPositionRouter), type(uint256).max);
    }

    function testBeforeInitializeAllowsPoolCreation() public {
        manager.initialize(key, SQRT_RATIO_1_1);
    }

    function testBeforeInitializeRevertsIfFee() public {
        vm.expectRevert(TWALHook.OnlyOneOraclePoolAllowed.selector);
        manager.initialize(
            PoolKey(
                Currency.wrap(address(token0)), Currency.wrap(address(token1)), 1, MAX_TICK_SPACING, truncatedOracle
            ),
            SQRT_RATIO_1_1
        );
    }

    function testBeforeInitializeRevertsIfNotMaxTickSpacing() public {
        vm.expectRevert(TWALHook.OnlyOneOraclePoolAllowed.selector);
        manager.initialize(
            PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 0, 60, truncatedOracle),
            SQRT_RATIO_1_1
        );
    }

    function testAfterInitializeState() public {
        manager.initialize(key, SQRT_RATIO_2_1);
        TWALHook.ObservationState memory observationState = truncatedOracle.getState(key);
        assertEq(observationState.index, 0);
        assertEq(observationState.cardinality, 1);
        assertEq(observationState.cardinalityNext, 1);
    }

    function testAfterInitializeObservation() public {
        manager.initialize(key, SQRT_RATIO_2_1);
        Oracle.Observation memory observation = truncatedOracle.getObservation(key, 0);
        assertTrue(observation.initialized);
        assertEq(observation.blockTimestamp, 1);
        assertEq(observation.tickCumulative, 0);
        assertEq(observation.secondsPerLiquidityCumulativeX128, 0);
    }

    function testAfterInitializeObserve0() public {
        manager.initialize(key, SQRT_RATIO_2_1);
        uint32[] memory secondsAgo = new uint32[](1);
        secondsAgo[0] = 0;
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            truncatedOracle.observe(key, secondsAgo);
        assertEq(tickCumulatives.length, 1);
        assertEq(secondsPerLiquidityCumulativeX128s.length, 1);
        assertEq(tickCumulatives[0], 0);
        assertEq(secondsPerLiquidityCumulativeX128s[0], 0);
    }

    function testBeforeModifyPositionNoObservations() public {
        manager.initialize(key, SQRT_RATIO_2_1);
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(
                TickMath.minUsableTick(MAX_TICK_SPACING), TickMath.maxUsableTick(MAX_TICK_SPACING), 1000
            )
        );

        TWALHook.ObservationState memory observationState = truncatedOracle.getState(key);
        assertEq(observationState.index, 0);
        assertEq(observationState.cardinality, 1);
        assertEq(observationState.cardinalityNext, 1);

        Oracle.Observation memory observation = truncatedOracle.getObservation(key, 0);
        assertTrue(observation.initialized);
        assertEq(observation.blockTimestamp, 1);
        assertEq(observation.tickCumulative, 0);
        assertEq(observation.secondsPerLiquidityCumulativeX128, 0);
    }

    function testBeforeModifyPositionObservation() public {
        manager.initialize(key, SQRT_RATIO_2_1);
        truncatedOracle.setTime(3); // advance 2 seconds
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(
                TickMath.minUsableTick(MAX_TICK_SPACING), TickMath.maxUsableTick(MAX_TICK_SPACING), 1000
            )
        );

        TWALHook.ObservationState memory observationState = truncatedOracle.getState(key);
        assertEq(observationState.index, 0);
        assertEq(observationState.cardinality, 1);
        assertEq(observationState.cardinalityNext, 1);

        Oracle.Observation memory observation = truncatedOracle.getObservation(key, 0);
        assertTrue(observation.initialized);
        assertEq(observation.blockTimestamp, 3);
        assertEq(observation.tickCumulative, 13862);
        assertEq(observation.secondsPerLiquidityCumulativeX128, 680564733841876926926749214863536422912);
    }

    function testBeforeModifyPositionObservationAndCardinality() public {
        manager.initialize(key, SQRT_RATIO_2_1);
        truncatedOracle.setTime(3); // advance 2 seconds
        truncatedOracle.increaseCardinalityNext(key, 2);
        TWALHook.ObservationState memory observationState = truncatedOracle.getState(key);
        assertEq(observationState.index, 0);
        assertEq(observationState.cardinality, 1);
        assertEq(observationState.cardinalityNext, 2);

        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(
                TickMath.minUsableTick(MAX_TICK_SPACING), TickMath.maxUsableTick(MAX_TICK_SPACING), 1000
            )
        );

        // cardinality is updated
        observationState = truncatedOracle.getState(key);
        assertEq(observationState.index, 1);
        assertEq(observationState.cardinality, 2);
        assertEq(observationState.cardinalityNext, 2);

        // index 0 is untouched
        Oracle.Observation memory observation = truncatedOracle.getObservation(key, 0);
        assertTrue(observation.initialized);
        assertEq(observation.blockTimestamp, 1);
        assertEq(observation.tickCumulative, 0);
        assertEq(observation.secondsPerLiquidityCumulativeX128, 0);

        // index 1 is written
        observation = truncatedOracle.getObservation(key, 1);
        assertTrue(observation.initialized);
        assertEq(observation.blockTimestamp, 3);
        assertEq(observation.tickCumulative, 13862);
        assertEq(observation.secondsPerLiquidityCumulativeX128, 680564733841876926926749214863536422912);
    }
}
