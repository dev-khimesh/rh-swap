// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/ERC20.sol";
import {Factory} from "../src/Factory.sol";
import {Router} from "../src/Router.sol";
import {Pair} from "../src/Pair.sol";

contract SwapTest is Test {
    Factory factory;
    Router router;
    MockERC20 usdc; // test USDC hub token
    MockERC20 wbtc; // arbitrary "any coin"
    MockERC20 doge; // second "any coin", for multi-hop

    address alice = address(0xA11CE);
    address lp = address(0xB0B);

    function setUp() public {
        factory = new Factory();
        router = new Router(address(factory));
        usdc = new MockERC20("Test USD Coin", "tUSDC", 6);
        wbtc = new MockERC20("Test Wrapped BTC", "tWBTC", 8);
        doge = new MockERC20("Test Doge", "tDOGE", 18);

        // Seed the LP with balances and add liquidity for both pairs.
        usdc.mint(lp, 2_000_000e6);
        wbtc.mint(lp, 20e8);
        doge.mint(lp, 10_000_000e18);

        vm.startPrank(lp);
        usdc.approve(address(router), type(uint256).max);
        wbtc.approve(address(router), type(uint256).max);
        doge.approve(address(router), type(uint256).max);

        // 1,000,000 tUSDC : 10 tWBTC  -> ~100k USDC per BTC
        router.addLiquidity(address(usdc), address(wbtc), 1_000_000e6, 10e8, lp);
        // 1,000,000 tUSDC : 10,000,000 tDOGE -> ~0.10 USDC per DOGE
        router.addLiquidity(address(usdc), address(doge), 1_000_000e6, 10_000_000e18, lp);
        vm.stopPrank();
    }

    function test_directSwap_usdcToWbtc() public {
        usdc.mint(alice, 100_000e6);
        vm.startPrank(alice);
        usdc.approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(wbtc);

        uint256[] memory quote = router.getAmountsOut(100_000e6, path);
        uint256 out = router.swapExactTokensForTokens(
            100_000e6, quote[1], path, alice, block.timestamp + 1
        )[1];
        vm.stopPrank();

        assertEq(out, quote[1], "output matches quote");
        assertEq(wbtc.balanceOf(alice), out, "alice received wbtc");
        assertGt(out, 0, "nonzero output");
    }

    function test_multiHop_wbtcToDogeViaUsdc() public {
        wbtc.mint(alice, 1e8);
        vm.startPrank(alice);
        wbtc.approve(address(router), type(uint256).max);

        address[] memory path = new address[](3);
        path[0] = address(wbtc);
        path[1] = address(usdc);
        path[2] = address(doge);

        uint256[] memory amounts = router.getAmountsOut(1e8, path);
        router.swapExactTokensForTokens(1e8, amounts[2], path, alice, block.timestamp + 1);
        vm.stopPrank();

        assertEq(doge.balanceOf(alice), amounts[2], "alice received doge");
        assertGt(amounts[2], 0, "nonzero doge out");
    }

    function test_slippageGuardReverts() public {
        usdc.mint(alice, 100_000e6);
        vm.startPrank(alice);
        usdc.approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(wbtc);

        uint256[] memory quote = router.getAmountsOut(100_000e6, path);
        vm.expectRevert(bytes("Router: slippage"));
        router.swapExactTokensForTokens(100_000e6, quote[1] + 1, path, alice, block.timestamp + 1);
        vm.stopPrank();
    }

    function test_deadlineReverts() public {
        usdc.mint(alice, 1e6);
        vm.startPrank(alice);
        usdc.approve(address(router), type(uint256).max);
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(wbtc);
        vm.warp(1000);
        vm.expectRevert(bytes("Router: expired"));
        router.swapExactTokensForTokens(1e6, 0, path, alice, 999);
        vm.stopPrank();
    }

    function test_constantProductHolds() public {
        (uint112 r0Before, uint112 r1Before) = _reserves(address(usdc), address(wbtc));
        uint256 kBefore = uint256(r0Before) * r1Before;

        usdc.mint(alice, 50_000e6);
        vm.startPrank(alice);
        usdc.approve(address(router), type(uint256).max);
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(wbtc);
        router.swapExactTokensForTokens(50_000e6, 0, path, alice, block.timestamp + 1);
        vm.stopPrank();

        (uint112 r0After, uint112 r1After) = _reserves(address(usdc), address(wbtc));
        uint256 kAfter = uint256(r0After) * r1After;
        assertGe(kAfter, kBefore, "k must not decrease (fee accrues to pool)");
    }

    function _reserves(address a, address b) internal view returns (uint112, uint112) {
        (address t0, address t1) = a < b ? (a, b) : (b, a);
        Pair p = Pair(factory.getPair(t0, t1));
        return p.getReserves();
    }
}
