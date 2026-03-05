// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockERC20.sol";
import "./MockAToken.sol";

/**
 * @title MockAavePool
 * @dev Minimal Aave V3 Pool mock used in FlashVault unit tests.
 *
 * Flow:
 *  supply()   → pulls USDT from the vault, mints aTokens 1:1 to `onBehalfOf`.
 *  withdraw() → burns aTokens from the caller (vault), sends USDT 1:1 to `to`.
 *
 * The mock holds USDT after supply() and releases it on withdraw(), exactly
 * mirroring the real Aave pool's token custody semantics without any interest.
 * Yield is simulated externally via MockAToken.simulateYield().
 */
contract MockAavePool {
    MockERC20 public immutable usdt;
    MockAToken public immutable aToken;

    constructor(address _usdt, address _aToken) {
        usdt = MockERC20(_usdt);
        aToken = MockAToken(_aToken);
    }

    /**
     * @notice Mirror of Aave V3 Pool.supply().
     *         Pulls `amount` USDT from msg.sender (FlashVault) and mints
     *         the same amount of aTokens to `onBehalfOf`.
     */
    function supply(
        address /*asset — ignored, always our usdt mock*/,
        uint256 amount,
        address onBehalfOf,
        uint16 /*referralCode*/
    ) external {
        // Transfer USDT from vault to this pool (custody)
        usdt.transferFrom(msg.sender, address(this), amount);
        // Mint aTokens to the vault (onBehalfOf)
        aToken.mint(onBehalfOf, amount);
    }

    /**
     * @notice Mirror of Aave V3 Pool.withdraw().
     *         Burns `amount` aTokens from the caller (FlashVault) and
     *         transfers the same amount of USDT to `to`.
     * @return The amount withdrawn.
     */
    function withdraw(
        address /*asset*/,
        uint256 amount,
        address to
    ) external returns (uint256) {
        // Burn aTokens from the caller
        aToken.burn(msg.sender, amount);
        // Release USDT from pool custody
        usdt.transfer(to, amount);
        return amount;
    }
}
