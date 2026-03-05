// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IFlashOracle
 * @dev Interfaz del oracle de precios del protocolo FlashBet.
 *
 * ## ¿Por qué una interfaz?
 *  FlashPredMarket necesita precios de BTC y ETH, pero no le importa
 *  de dónde vienen. Al programar contra esta interfaz en lugar de una
 *  implementación concreta, el mercado puede recibir:
 *   - FlashOracle: usa Chainlink en producción (mainnet).
 *   - MockFlashOracle: simula precios en testnet o tests unitarios.
 *
 *  Esto se llama el "Principio de Inversión de Dependencias" (SOLID).
 *  El contrato de alto nivel (FlashPredMarket) depende de una abstracción,
 *  no de una implementación concreta.
 *
 * ## Precios con 8 decimales (estándar Chainlink)
 *  Los precios tienen 8 decimales para mantener consistencia con Chainlink.
 *  Ejemplos:
 *    BTC a $66,000 → 6_600_000_000_000 (66000 × 1e8)
 *    ETH a  $2,500 →   250_000_000_000 (2500  × 1e8)
 *
 *  En el frontend, para mostrar el precio legible:
 *    Number(price) / 1e8 = precio en USD con hasta 8 decimales.
 *
 * ## Símbolos soportados
 *  "BTC" → precio BTC/USD
 *  "ETH" → precio ETH/USD
 *  (extensible: una implementación podría soportar "SOL", "MATIC", etc.)
 */
interface IFlashOracle {
    /**
     * @notice Retorna el último precio conocido para el símbolo dado.
     * @dev Puede revertir en implementaciones que hagan validaciones:
     *      - FlashOracle: revierte si el precio es stale o <= 0 (Chainlink).
     *      - MockFlashOracle: retorna 0 si el símbolo no está configurado.
     *
     * @param symbol  Ticker del activo: "BTC" o "ETH".
     * @return price  Precio con 8 decimales (ej: 66000e8 para BTC a $66,000).
     */
    function getPrice(
        string calldata symbol
    ) external view returns (int256 price);
}
