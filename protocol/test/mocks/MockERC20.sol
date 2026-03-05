// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @dev Simple ERC-20 with unrestricted public mint and burn.
 *      Used in unit tests as a stand-in for USDT (pass decimals = 6).
 */
contract MockERC20 is ERC20 {
    uint8 private immutable _dec;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _dec = decimals_;
    }

    /// @dev Anyone can mint — test helper only.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Anyone can burn — test helper only.
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }
}
