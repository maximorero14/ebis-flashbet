// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./MockERC20.sol";

/**
 * @title MockAToken
 * @dev Simulates an Aave aToken (aUSDT) in unit tests.
 *
 *  - MockAavePool mints/burns this token via the inherited helpers.
 *  - `simulateYield` mints extra tokens directly to the vault address,
 *    mimicking the interest that accrues in real Aave over time.
 */
contract MockAToken is MockERC20 {
    constructor() MockERC20("Aave Sepolia USDT", "aSepoliaUSDT", 6) {}

    /**
     * @notice Simulate interest accrual by minting yield tokens to `vault`.
     * @dev Call this in tests after a time-warp to model Aave yield.
     * @param vault       The FlashVault address holding aTokens.
     * @param yieldAmount Amount of yield (6 decimals) to add.
     */
    function simulateYield(address vault, uint256 yieldAmount) external {
        _mint(vault, yieldAmount);
    }
}
