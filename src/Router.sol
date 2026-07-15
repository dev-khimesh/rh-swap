// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Factory} from "./Factory.sol";
import {Pair} from "./Pair.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
}

/// @notice User-facing entry point. Handles liquidity and multi-hop swaps so a
/// caller can trade USDC -> any coin (direct), or coin -> coin routed via USDC.
contract Router {
    Factory public immutable factory;

    modifier ensure(uint256 deadline) {
        require(block.timestamp <= deadline, "Router: expired");
        _;
    }

    constructor(address _factory) {
        factory = Factory(_factory);
    }

    function _sortTokens(address a, address b) internal pure returns (address t0, address t1) {
        (t0, t1) = a < b ? (a, b) : (b, a);
    }

    /// @notice x*y=k output amount for a single hop, net of the 0.30% fee.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256)
    {
        require(amountIn > 0, "Router: insufficient input");
        require(reserveIn > 0 && reserveOut > 0, "Router: no liquidity");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        return numerator / denominator;
    }

    function _reservesFor(address pair, address tokenIn)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        (uint112 r0, uint112 r1) = Pair(pair).getReserves();
        address token0 = Pair(pair).token0();
        (reserveIn, reserveOut) = tokenIn == token0 ? (r0, r1) : (r1, r0);
    }

    /// @notice Quote a full path without executing.
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        public
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Router: bad path");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (address t0, address t1) = _sortTokens(path[i], path[i + 1]);
            address pair = factory.getPair(t0, t1);
            require(pair != address(0), "Router: no pair");
            (uint256 rIn, uint256 rOut) = _reservesFor(pair, path[i]);
            amounts[i + 1] = getAmountOut(amounts[i], rIn, rOut);
        }
    }

    /// @notice Add liquidity to (tokenA, tokenB), creating the pair if needed.
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address to
    ) external returns (uint256 liquidity) {
        (address t0, address t1) = _sortTokens(tokenA, tokenB);
        address pair = factory.getPair(t0, t1);
        if (pair == address(0)) pair = factory.createPair(tokenA, tokenB);

        require(IERC20(tokenA).transferFrom(msg.sender, pair, amountA), "Router: pull A");
        require(IERC20(tokenB).transferFrom(msg.sender, pair, amountB), "Router: pull B");
        liquidity = Pair(pair).mint(to);
    }

    /// @notice Remove liquidity from (tokenA, tokenB) and return underlying tokens.
    /// @dev Transfers LP tokens from caller to the pair, then burns them to release underlying.
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        (address t0, address t1) = _sortTokens(tokenA, tokenB);
        address pair = factory.getPair(t0, t1);
        require(pair != address(0), "Router: no pair");

        require(IERC20(pair).transferFrom(msg.sender, pair, liquidity), "Router: pull LP");

        (uint256 a0, uint256 a1) = Pair(pair).burn(to);
        (amountA, amountB) = tokenA == t0 ? (a0, a1) : (a1, a0);

        require(amountA >= amountAMin, "Router: insufficient A");
        require(amountB >= amountBMin, "Router: insufficient B");
    }

    /// @notice Swap an exact amountIn along `path`, requiring at least amountOutMin.
    /// For "USDC -> any coin" use a 2-element path; for coin->coin route via USDC.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: slippage");

        address firstPair = _pairFor(path[0], path[1]);
        require(
            IERC20(path[0]).transferFrom(msg.sender, firstPair, amounts[0]),
            "Router: pull in"
        );
        _swap(amounts, path, to);
    }

    function _swap(uint256[] memory amounts, address[] calldata path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            address input = path[i];
            address output = path[i + 1];
            (address t0,) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == t0 ? (uint256(0), amountOut) : (amountOut, uint256(0));

            address pair = _pairFor(input, output);
            // recipient is the next pair in the path, or the final `_to`
            address to = i < path.length - 2
                ? _pairFor(output, path[i + 2])
                : _to;
            Pair(pair).swap(amount0Out, amount1Out, to);
        }
    }

    function _pairFor(address a, address b) internal view returns (address) {
        (address t0, address t1) = _sortTokens(a, b);
        return factory.getPair(t0, t1);
    }
}
