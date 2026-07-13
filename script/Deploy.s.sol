// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../src/ERC20.sol";
import {Factory} from "../src/Factory.sol";
import {Router} from "../src/Router.sol";

/// @notice Deploys the swap system to Robinhood Chain and seeds two pools so
/// the DEX is immediately usable: tUSDC/tWBTC and tUSDC/tDOGE.
///
/// Run (testnet):
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url $RH_RPC_URL --private-key $PRIVATE_KEY --broadcast
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(pk);

        vm.startBroadcast(pk);

        Factory factory = new Factory();
        Router router = new Router(address(factory));

        // Test tokens. tUSDC is the hub asset every coin pairs against.
        MockERC20 usdc = new MockERC20("Test USD Coin", "tUSDC", 6);
        MockERC20 wbtc = new MockERC20("Test Wrapped BTC", "tWBTC", 8);
        MockERC20 doge = new MockERC20("Test Doge", "tDOGE", 18);

        // Mint starting inventory to the deployer.
        usdc.mint(me, 2_000_000e6);
        wbtc.mint(me, 20e8);
        doge.mint(me, 10_000_000e18);

        // Approve router and seed initial liquidity / prices.
        usdc.approve(address(router), type(uint256).max);
        wbtc.approve(address(router), type(uint256).max);
        doge.approve(address(router), type(uint256).max);

        router.addLiquidity(address(usdc), address(wbtc), 1_000_000e6, 10e8, me);      // ~100k USDC/BTC
        router.addLiquidity(address(usdc), address(doge), 1_000_000e6, 10_000_000e18, me); // ~0.10 USDC/DOGE

        vm.stopBroadcast();

        console2.log("Factory: ", address(factory));
        console2.log("Router:  ", address(router));
        console2.log("tUSDC:   ", address(usdc));
        console2.log("tWBTC:   ", address(wbtc));
        console2.log("tDOGE:   ", address(doge));
    }
}
