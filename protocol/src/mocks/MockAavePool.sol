// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MockAToken.sol";

/**
 * @title MockAavePool
 * @dev Simulación del Pool de Aave V3 para Sepolia testnet y tests unitarios.
 *      Implementa supply() y withdraw() con la misma firma que el pool real.
 *      FlashVault llama a estos métodos sin saber si es el mock o el pool real.
 *
 * ## ¿Cómo funciona Aave V3 en producción?
 *  Aave mantiene un "índice de liquidez" (liquidityIndex) que crece por segundo.
 *  Cuando hacés supply(1000 USDT), Aave te da tokens de deuda escalados:
 *    scaledBalance = 1000 / liquidityIndex
 *  Con el tiempo, el índice crece y tu aToken.balanceOf() refleja interés acumulado:
 *    balance = scaledBalance × liquidityIndex (crece solo, sin transacciones)
 *
 * ## ¿Cómo lo simula este mock?
 *  En lugar de crecimiento continuo (que requeriría un keeper o un estado global
 *  que varía por segundo), simplemente mintea más aTokens al momento del supply:
 *    supply(1000 USDT) → mint(vault, 1050 maUSDT)  ← 5% yield instantáneo
 *
 *  Efecto observable desde FlashVault:
 *    aToken.balanceOf(vault) = 1050
 *    totalDeposited          = 1000
 *    pendingYield            = 1050 - 1000 = 50 USDT
 *
 *  Esto es suficiente para demostrar harvestYield() en el TFM.
 *
 * ## Pre-requisito: seedYieldReserve
 *  El yield extra (5%) de los aTokens necesita USDT real para respaldarlo.
 *  Cuando vault llama withdraw(50), el pool debe tener 50 USDT disponibles.
 *  El deployer llama seedYieldReserve(amount) antes de cualquier depósito.
 *  Deploy.s.sol lo hace con 20 USDT (cubre ~5% sobre 400 USDT de depósitos).
 *
 * ## Compatible con IAavePool
 *  FlashVault solo necesita supply() y withdraw() → este mock los implementa.
 */
contract MockAavePool {
    using SafeERC20 for IERC20;

    /**
     * @notice Yield instantáneo acreditado en cada supply(). 500 bps = 5%.
     * @dev Simula el interés acumulado de Aave. En producción, este yield
     *      crece gradualmente por segundo. Aquí se aplica de golpe al depositar.
     */
    uint256 public constant YIELD_BPS = 500;

    /**
     * @notice Token de interés que el vault recibirá al hacer supply.
     *         Equivale al aUSDT de Aave (interest-bearing token).
     */
    MockAToken public immutable aToken;

    /**
     * @notice Token subyacente que el vault deposita (USDT en nuestro caso).
     */
    IERC20 public immutable underlying;

    // ─────────────────────── Errors ──────────────────────────────────────────

    error MockPool__AssetMismatch();              // El asset no es el underlying configurado
    error MockPool__InsufficientATokenBalance();  // Vault no tiene suficiente aToken para withdraw
    error MockPool__InsufficientReserve();        // El pool no tiene suficiente USDT para pagar

    // ─────────────────────── Constructor ─────────────────────────────────────

    /**
     * @notice Configura el pool con el token subyacente y el aToken.
     * @param _underlying  Dirección del token a depositar (USDT).
     * @param _aToken      Dirección del MockAToken desplegado previamente.
     */
    constructor(address _underlying, address _aToken) {
        underlying = IERC20(_underlying);
        aToken = MockAToken(_aToken);
    }

    /**
     * @notice Pre-carga el pool con USDT para respaldar los yield bonuses.
     * @dev DEBE llamarse antes de que el vault reciba cualquier depósito.
     *      Si no se precarga, withdraw() revertirá con InsufficientReserve
     *      cuando se intente cosechar el yield.
     *
     *      Cálculo: si esperás 400 USDT de depósitos totales, necesitás
     *      semillar al menos 400 * 5% = 20 USDT de reserva.
     *
     *      El caller necesita haber aprobado este contrato previamente.
     *
     * @param amount Cantidad de USDT de reserva de yield (6 decimales).
     */
    function seedYieldReserve(uint256 amount) external {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Acepta USDT del vault y mintea aTokens con 5% de yield bonus.
     * @dev En Aave real: supply() transfiere el USDT al pool y mintea aTokens
     *      en proporción 1:1 (el exceso aparece gradualmente vía el índice).
     *      Aquí: mintamos 105% de aTokens inmediatamente para simular yield acumulado.
     *
     * @param asset       Debe ser el token underlying (USDT).
     * @param amount      Cantidad de USDT a depositar (6 decimales).
     * @param onBehalfOf  Dirección que recibirá los aTokens (FlashVault).
     */
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 /*referralCode*/    // Ignorado — no hay programa de referidos en el mock
    ) external {
        // Verifica que el token sea el correcto (solo aceptamos USDT).
        if (asset != address(underlying)) revert MockPool__AssetMismatch();

        // Recibe el USDT del vault.
        underlying.safeTransferFrom(msg.sender, address(this), amount);

        // Calcula el yield bonus del 5%.
        // Ejemplo: deposit 1000 USDT → yieldBonus = 50 → mint 1050 aTokens
        uint256 yieldBonus = (amount * YIELD_BPS) / 10_000;

        // Mintea aTokens al vault: principal + yield inmediato
        // Esto hace que aToken.balanceOf(vault) > totalDeposited desde el momento 0.
        aToken.mint(onBehalfOf, amount + yieldBonus);
    }

    /**
     * @notice Retira USDT del pool quemando aTokens del llamador.
     * @dev En Aave real: withdraw() quema los aTokens y transfiere el USDT subyacente.
     *      Aquí: quemamos aTokens del msg.sender (FlashVault) y enviamos USDT a `to`.
     *
     *      El vault llama withdraw() en dos situaciones:
     *       1. redeem(amount): usuario quiere recuperar su USDT → to = usuario
     *       2. harvestYield(): cosechar yield → to = treasury
     *
     *      type(uint256).max como amount: retira TODO el balance de aTokens.
     *      (Mismo comportamiento que Aave real para "retirar todo".)
     *
     * @param asset   Debe ser USDT.
     * @param amount  Cantidad a retirar, o type(uint256).max para todo.
     * @param to      Destino del USDT retirado.
     * @return        Cantidad real retirada.
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        if (asset != address(underlying)) revert MockPool__AssetMismatch();

        // Si amount == max uint256, retirar todo el balance de aTokens del caller.
        if (amount == type(uint256).max) {
            amount = aToken.balanceOf(msg.sender);
        }

        // Verifica que el caller (vault) tenga suficiente aTokens para quemar.
        if (aToken.balanceOf(msg.sender) < amount) {
            revert MockPool__InsufficientATokenBalance();
        }

        // Verifica que el pool tenga suficiente USDT para pagar.
        // Si no se sembró suficiente reserva, esto revertirá en withdraw de yield.
        if (underlying.balanceOf(address(this)) < amount) {
            revert MockPool__InsufficientReserve();
        }

        // Quema los aTokens del vault (reducción del "depósito en Aave").
        aToken.burn(msg.sender, amount);

        // Transfiere el USDT al destino final.
        underlying.safeTransfer(to, amount);

        return amount;
    }
}
