// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal, self-contained ERC-20. No external deps so the project
/// compiles cleanly on Robinhood Chain tooling without npm/OZ installs.
contract ERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "ERC20: allowance");
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "ERC20: to zero");
        uint256 bal = balanceOf[from];
        require(bal >= value, "ERC20: balance");
        unchecked {
            balanceOf[from] = bal - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _mint(address to, uint256 value) internal {
        require(to != address(0), "ERC20: mint zero");
        totalSupply += value;
        unchecked {
            balanceOf[to] += value;
        }
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        uint256 bal = balanceOf[from];
        require(bal >= value, "ERC20: burn");
        unchecked {
            balanceOf[from] = bal - value;
            totalSupply -= value;
        }
        emit Transfer(from, address(0), value);
    }
}

/// @notice Openly-mintable test token for the Robinhood Chain testnet.
/// NOTE: This is a development stand-in, NOT real USDC. Circle's USDC is a
/// separate, issuer-controlled contract. Keep the symbol clearly a test token
/// (e.g. "tUSDC") so nobody mistakes it for a real stablecoin.
contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol, uint8 _decimals)
        ERC20(_name, _symbol, _decimals)
    {}

    /// @dev Permissionless faucet-style mint — fine for testnet, never for mainnet.
    function mint(address to, uint256 value) external {
        _mint(to, value);
    }
}
