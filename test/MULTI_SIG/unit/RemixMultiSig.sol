// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {IHooks} from "lib/v4-periphery/lib/v4-core/contracts/interfaces/IHooks.sol";
import {Hooks} from "lib/v4-periphery/lib/v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "lib/v4-periphery/lib/v4-core/contracts/interfaces/IPoolManager.sol";
import {CurrencyLibrary, Currency} from "lib/v4-periphery/lib/v4-core/contracts/types/Currency.sol";
import {PoolKey} from "lib/v4-periphery/lib/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "lib/v4-periphery/lib/v4-core/contracts/types/PoolId.sol";
import {MultiSigSwapHook} from "../../../src/MULTI_SIG/MultiSigSwapHook.sol";
import {MockERC20} from "@uniswap/v4-core/test/foundry-tests/utils/MockERC20.sol";
import {HookMiner} from "../utils/HookMiner.sol";
import {SafeCast} from "@uniswap/v4-core/contracts/libraries/SafeCast.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/contracts/test/PoolDonateTest.sol";

contract MultiSigTest {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using CurrencyLibrary for Currency;

    MultiSigSwapHook public hook;

    PoolKey poolKey;
    PoolId poolId;

    address manager;

    MockERC20 token0;
    MockERC20 token1;

    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;
    PoolDonateTest donateRouter;

    Currency currency0;
    Currency currency1;

    uint160 public constant SQRT_RATIO_1_1 = 79228162514264337593543950336;
    uint160 constant SQRT_RATIO_10_1 = 250541448375047931186413801569;
    int24 public constant MAX_TICK_SPACING = type(int16).max;
    uint256 constant MAX_DEADLINE = 12329839823;
    int24 constant TICK_SPACING = 60;
    bytes internal constant ZERO_BYTES = bytes("");

    event TestLog(string testName, string message);

    event Failure(string message);

    constructor(address _manager) {
        manager = _manager;
    }

    function setUp() public {
        token0 = new MockERC20("TestA", "A", 18, 2 ** 128);
        token1 = new MockERC20("TestB", "B", 18, 2 ** 128);

        (currency0, currency1) = sort(token0, token1);

        address[] memory signers = new address[](2);
        signers[0] = address(this);
        signers[1] = address(0x1234);

        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_FLAG);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            0,
            type(MultiSigSwapHook).creationCode,
            abi.encode(address(manager))
        );

        hook = new MultiSigSwapHook{salt: salt}(
            IPoolManager(address(manager)),
            signers,
            2
        );

        require(
            address(hook) == hookAddress,
            "FairTradeTest: Hook address mismatch"
        );

        poolKey = PoolKey(currency0, currency1, 0, MAX_TICK_SPACING, hook);
        poolId = poolKey.toId();

        modifyPositionRouter = new PoolModifyPositionTest(
            IPoolManager(manager)
        );
        swapRouter = new PoolSwapTest(IPoolManager(manager));

        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);
        token0.approve(address(modifyPositionRouter), type(uint256).max);
        token1.approve(address(modifyPositionRouter), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
    }

    function sort(
        MockERC20 tokenA,
        MockERC20 tokenB
    ) internal pure returns (Currency _currency0, Currency _currency1) {
        if (address(tokenA) < address(tokenB)) {
            (_currency0, _currency1) = (
                Currency.wrap(address(tokenA)),
                Currency.wrap(address(tokenB))
            );
        } else {
            (_currency0, _currency1) = (
                Currency.wrap(address(tokenB)),
                Currency.wrap(address(tokenA))
            );
        }
    }

    function testApproveSwap() public {
        bytes32 swapHash = keccak256(abi.encode(keccak256("mockSwapParams")));

        hook.approveSwap(swapHash);
        (uint256 count, bool hasSigned) = hook.getApprovalDetails(swapHash);

        if (count == 1) {
            emit TestLog("Count test", "PASSED: Count is 1");
        } else {
            emit Failure("FAILED: Count is not 1");
        }

        if (hasSigned) {
            emit TestLog("hasSigned test", "PASSED: hasSigned is true");
        } else {
            emit Failure("FAILED: hasSigned is not true");
        }
    }

    receive() external payable {}
}
