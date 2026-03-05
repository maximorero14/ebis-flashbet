// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Treasury
 * @dev Contrato receptor de todos los ingresos del protocolo FlashBet.
 *
 * ## ¿Qué ingresos recibe?
 *
 *  1. Trading fees (1% de cada apuesta):
 *     Flujo: usuario.placeBet() → 1% enviado en $FLASH al treasury.
 *     Ejemplo: alguien apuesta 1000 $FLASH → 10 $FLASH van aquí.
 *
 *  2. Yield de Aave (interés acumulado del vault):
 *     Flujo: harvestYield() → USDT excedente de Aave enviado aquí.
 *     Ejemplo: si hay 5 USDT de interés acumulado, esos 5 USDT llegan aquí.
 *
 * El treasury acumula $FLASH y USDT. El owner puede retirarlos en cualquier momento.
 *
 * ## ¿Por qué este contrato es tan simple?
 *  Intencionalmente minimalista para el TFM:
 *  - Sin vesting (no hay lock de tokens con cliff + vest period)
 *  - Sin splits automáticos (no hay % para equipo, % para stakers, etc.)
 *  - Sin gobernanza (no hay DAO que vote cómo gastar los fondos)
 *  - Solo el owner retira (control centralizado — adecuado para un protocolo nuevo)
 *
 *  En un protocolo DeFi maduro, el treasury tendría:
 *  - Multisig (Gnosis Safe) como owner
 *  - Vesting para contribuidores
 *  - Splits automáticos a buyback, staking rewards, etc.
 *  - Gobernanza on-chain (Governor Bravo, OpenZeppelin Governor)
 *
 * ## Seguridad
 *  - SafeERC20: previene problemas con tokens no estándar (USDT, etc.)
 *  - Checks previos: saldo suficiente antes de transferir (evita revert por insuficiente)
 *  - Solo owner: función withdraw restringida
 */
contract Treasury is Ownable {
    using SafeERC20 for IERC20;

    // ─────────────────────── Custom errors ───────────────────────────────────

    error Treasury__AmountZero();           // amount == 0 en withdraw
    error Treasury__ZeroAddress();          // token o recipient == address(0)
    error Treasury__InsufficientBalance();  // El treasury no tiene suficiente saldo

    // ─────────────────────── Events ──────────────────────────────────────────

    /**
     * @dev Emitido en cada retiro exitoso.
     *      El frontend (Admin Panel) puede escuchar este evento.
     */
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    // ─────────────────────── Constructor ─────────────────────────────────────

    /**
     * @notice Despliega el treasury con `_owner` como administrador.
     * @dev En Deploy.s.sol, el owner es el deployer del protocolo.
     *      El treasury comienza sin fondos — los recibe automáticamente
     *      de FlashPredMarket (fees) y FlashVault (yield).
     *
     * @param _owner Dirección del administrador (puede retirar fondos).
     */
    constructor(address _owner) Ownable(_owner) {}

    // ─────────────────────── Withdraw ────────────────────────────────────────

    /**
     * @notice Retira `amount` del token `token` hacia la dirección `to`.
     * @dev Solo el owner puede retirar.
     *      Funciona con cualquier ERC-20 que el treasury haya acumulado.
     *      Los tokens acumulados son: $FLASH (fees) y USDT (yield de Aave).
     *
     * @param token   Dirección del ERC-20 a retirar ($FLASH o USDT).
     * @param to      Dirección de destino del retiro.
     * @param amount  Cantidad a retirar (en unidades del token, 6 decimales).
     */
    function withdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        // Validaciones básicas antes de cualquier operación.
        if (token == address(0)) revert Treasury__ZeroAddress();
        if (to == address(0)) revert Treasury__ZeroAddress();
        if (amount == 0) revert Treasury__AmountZero();

        // Verifica que el treasury tenga saldo suficiente antes de intentar transferir.
        // Sin este check, la transferencia revertería de todas formas, pero el error
        // sería menos claro (dependería del token específico).
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal < amount) revert Treasury__InsufficientBalance();

        // Transfiere el token hacia `to`. SafeERC20 maneja tokens no estándar.
        IERC20(token).safeTransfer(to, amount);

        emit Withdrawn(token, to, amount);
    }

    // ─────────────────────── View ────────────────────────────────────────────

    /**
     * @notice Retorna el saldo del treasury para un token dado.
     * @dev El Admin Panel del frontend llama esto para mostrar:
     *      - balance($FLASH) → fees acumulados
     *      - balance(USDT)   → yield cosechado aún no retirado
     *
     * @param token Dirección del ERC-20 a consultar.
     * @return Saldo del treasury en ese token (6 decimales).
     */
    function balance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
