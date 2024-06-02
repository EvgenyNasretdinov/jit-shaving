// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {TWALHook} from "../../../src/TWALHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

contract TruncatedOracleImplementation is TWALHook {
    uint32 public time;

    constructor(IPoolManager _poolManager, TWALHook addressToEtch) TWALHook(_poolManager) {
        Hooks.validateHookAddress(addressToEtch, getHookPermissions());
    }

    // make this a no-op in testing
    function validateHookAddress(BaseHook _this) internal pure override {}

    function setTime(uint32 _time) external {
        time = _time;
    }

    function _blockTimestamp() internal view override returns (uint32) {
        return time;
    }
}
