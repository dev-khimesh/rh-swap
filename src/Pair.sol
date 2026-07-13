// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "./ERC20.sol";

interface IERC20Minimal {
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

/// @notice Constant-product (x*y=k) liquidity pair, Uniswap-V2 style.
/// LP shares are themselves an ERC-20 ("RH-LP"). 0.30% swap fee stays in the pool.
contract Pair is ERC20 {
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    address public immutable factory;
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "Pair: locked");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() ERC20("Robinhood Chain LP", "RH-LP", 18) {
        factory = msg.sender;
    }

    /// @dev Called once by the factory right after deployment.
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "Pair: forbidden");
        require(token0 == address(0), "Pair: initialized");
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    function _update(uint256 balance0, uint256 balance1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "Pair: overflow");
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        emit Sync(reserve0, reserve1);
    }

    /// @notice Mint LP shares. Caller must have already transferred both tokens in.
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        uint256 balance0 = IERC20Minimal(token0).balanceOf(address(this));
        uint256 balance1 = IERC20Minimal(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(1), MINIMUM_LIQUIDITY); // permanently lock the first shares
        } else {
            uint256 l0 = (amount0 * _totalSupply) / _reserve0;
            uint256 l1 = (amount1 * _totalSupply) / _reserve1;
            liquidity = l0 < l1 ? l0 : l1;
        }
        require(liquidity > 0, "Pair: insufficient liquidity minted");
        _mint(to, liquidity);
        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }

    /// @notice Burn LP shares held by this contract and return underlying tokens.
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        uint256 balance0 = IERC20Minimal(token0).balanceOf(address(this));
        uint256 balance1 = IERC20Minimal(token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        uint256 _totalSupply = totalSupply;
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "Pair: insufficient liquidity burned");

        _burn(address(this), liquidity);
        require(IERC20Minimal(token0).transfer(to, amount0), "Pair: t0 fail");
        require(IERC20Minimal(token1).transfer(to, amount1), "Pair: t1 fail");

        balance0 = IERC20Minimal(token0).balanceOf(address(this));
        balance1 = IERC20Minimal(token1).balanceOf(address(this));
        _update(balance0, balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /// @notice Low-level swap. Router computes amounts; here we enforce the invariant.
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external lock {
        require(amount0Out > 0 || amount1Out > 0, "Pair: insufficient output");
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "Pair: insufficient liquidity");
        require(to != token0 && to != token1, "Pair: invalid to");

        if (amount0Out > 0) require(IERC20Minimal(token0).transfer(to, amount0Out), "Pair: t0 fail");
        if (amount1Out > 0) require(IERC20Minimal(token1).transfer(to, amount1Out), "Pair: t1 fail");

        uint256 balance0 = IERC20Minimal(token0).balanceOf(address(this));
        uint256 balance1 = IERC20Minimal(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "Pair: insufficient input");

        // 0.30% fee: check k with balances adjusted by fee (scaled by 1000).
        uint256 balance0Adj = balance0 * 1000 - amount0In * 3;
        uint256 balance1Adj = balance1 * 1000 - amount1In * 3;
        require(
            balance0Adj * balance1Adj >= uint256(_reserve0) * uint256(_reserve1) * (1000 ** 2),
            "Pair: K"
        );

        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
