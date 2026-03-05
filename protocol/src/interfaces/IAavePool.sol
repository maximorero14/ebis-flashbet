// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IAavePool
 * @dev Interfaz mínima del Pool de Aave V3 necesaria para FlashVault.
 *
 * ## ¿Por qué una interfaz mínima y no el IPool completo de Aave?
 *  El IPool completo de Aave V3 tiene decenas de funciones (borrow, repay,
 *  flashloan, liquidate, etc.). FlashVault solo necesita supply() y withdraw().
 *  Usar la interfaz completa agregaría dependencias innecesarias y haría
 *  el código más difícil de leer y auditar.
 *
 *  Este patrón de "interfaz mínima" (narrow interface) es una buena práctica:
 *  solo exponer lo que realmente se usa — principio de Interface Segregation (SOLID).
 *
 * ## Implementaciones compatibles
 *  Cualquier contrato que implemente estas dos funciones con estas firmas es válido:
 *   - Pool de Aave V3 real (mainnet, Sepolia con Aave desplegado)
 *   - MockAavePool (este proyecto: testnet/tests sin Aave real)
 *
 * ## Precios de los tokens
 *  Aave V3 soporta cualquier token ERC-20 con suficiente liquidez en el pool.
 *  En nuestro caso, siempre pasamos USDT como `asset`.
 */
interface IAavePool {

    /**
     * @notice Suministra `amount` de `asset` al pool de Aave.
     * @dev El pool transfiere aTokens a `onBehalfOf` en proporción 1:1
     *      (en Aave real, el saldo de aTokens crece con el tiempo via el índice).
     *
     *      PRE-REQUISITO: el caller debe haber aprobado al pool para al menos
     *      `amount` del `asset`. FlashVault usa forceApprove() justo antes de llamar.
     *
     * @param asset        Token a depositar (USDT en nuestro caso).
     * @param amount       Cantidad a depositar (6 decimales para USDT).
     * @param onBehalfOf   Dirección que recibirá los aTokens (FlashVault en nuestro caso).
     * @param referralCode Código de referido para el programa de Aave (0 si no aplica).
     */
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @notice Retira `amount` de `asset` del pool de Aave.
     * @dev Quema los aTokens del msg.sender y transfiere el USDT a `to`.
     *      El caller debe ser quien tiene los aTokens (FlashVault en nuestro caso).
     *
     *      Uso especial: amount = type(uint256).max → retira TODO el balance disponible.
     *      Esto es conveniente para retirar el saldo completo sin calcular el amount exacto.
     *
     * @param asset   Token a retirar (USDT en nuestro caso).
     * @param amount  Cantidad a retirar, o type(uint256).max para retirar todo.
     * @param to      Destino del USDT retirado (usuario en redeem, treasury en harvest).
     * @return        Cantidad real retirada (puede diferir del amount si se usa max).
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}
