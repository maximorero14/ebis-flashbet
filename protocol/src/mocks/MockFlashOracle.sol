// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../../src/interfaces/IFlashOracle.sol";

/**
 * @title MockFlashOracle
 * @dev Oracle de precios simulado para Sepolia testnet y tests unitarios.
 *      Implementa la misma interfaz IFlashOracle que FlashOracle (producción).
 *      FlashPredMarket recibe cualquiera de los dos en su constructor.
 *
 * ## ¿Por qué no usar FlashOracle (Chainlink real) en Sepolia?
 *  Los feeds de Chainlink en Sepolia son lentos, poco fiables, y a veces
 *  el precio no cambia entre openRound() y resolveRound() (60-300s después).
 *  Si el precio es idéntico, finalPrice == referencePrice → resultado siempre empata.
 *  MockFlashOracle resuelve esto con simulación de volatilidad en cadena.
 *
 * ## Dos modos de operación
 *
 *  simulationEnabled = false (DEFAULT):
 *    getPrice() devuelve EXACTAMENTE el precio base configurado con setPrice().
 *    Usado en tests unitarios: resultados deterministas y verificables.
 *    Ejemplo: setPrice("BTC", 30_000e8) → getPrice("BTC") siempre retorna 30_000e8.
 *
 *  simulationEnabled = true (SEPOLIA DEPLOY):
 *    getPrice() agrega ruido pseudo-aleatorio al precio base.
 *    Ruido derivado de block.timestamp y blockhash → cambia cada bloque/30s.
 *    Garantiza que openRound() ≠ resolveRound() aunque sean seguidos.
 *    Activado automáticamente por Deploy.s.sol después del deploy.
 *
 * ## Cálculo del ruido (volatilityBps = 150 = ±1.5%)
 *
 *  COMPONENTE LENTO (cambia cada 30 segundos):
 *    seed = keccak256(block.timestamp / 30, symbolHash)
 *    dev  = base * (seed % 301 - 150) / 10_000  → [-1.5%, +1.5%] del precio base
 *    Simula una "tendencia" que dura 30s — asegura diferencia entre open y resolve.
 *
 *  COMPONENTE RÁPIDO (cambia cada bloque, ~12s en Sepolia):
 *    seed = keccak256(blockhash(block.number - 1), symbolHash)
 *    dev  = base * (seed % 41 - 20) / 100_000  → [-0.02%, +0.02%]
 *    Agrega micro-ruido cosmético para que el precio parezca "vivo" en el UI.
 *
 *  PRECIO FINAL = base + slowDev + fastDev
 *
 *  Con BTC en $84,000:
 *    slowDev máx = ±$1,260  (dominante: ±1.5%)
 *    fastDev máx = ±$16.8   (cosmético: ±0.02%)
 *    Desviación total máx: ±$1,277 (~±1.52%)
 *
 * ## Uso en el proyecto
 *  - Deploy.s.sol:                    deployado en Sepolia (simulación ON)
 *  - FlashBetPredMarketDemo.s.sol:    deployado para demos (simulación ON)
 *  - FlashPredMarket.t.sol:           tests unitarios (simulación OFF)
 *  - FlashVault.t.sol:                no usado (el vault no necesita oracle)
 */
contract MockFlashOracle is IFlashOracle {

    // ─────────────────────── Custom errors ───────────────────────────────────

    error MockFlashOracle__VolatilityTooHigh(); // bps > 500 in setVolatility()

    // ─────────────────────── Storage ─────────────────────────────────────────

    /**
     * @dev Precios base en 8 decimales (compatible con Chainlink).
     *      Clave: keccak256 del símbolo ("BTC", "ETH").
     *      Valor: precio × 1e8. Ejemplo: BTC a $84,000 → 84_000e8.
     */
    mapping(bytes32 => int256) private _basePrices;

    /**
     * @notice Si true, getPrice() agrega ruido pseudo-aleatorio al precio base.
     * @dev False por defecto — los tests unitarios necesitan resultados exactos.
     *      Se activa en Sepolia llamando enableSimulation() desde Deploy.s.sol.
     */
    bool public simulationEnabled;

    /**
     * @notice Volatilidad máxima en basis points. 150 = ±1.5%. Máximo 500 (±5%).
     * @dev Controla cuánto puede desviarse el precio simulado del precio base.
     *      Un BPS más alto hace la simulación más dramática pero menos realista.
     */
    uint256 public volatilityBps = 150;

    // ─────────────────────── Events ──────────────────────────────────────────

    event PriceUpdated(string indexed symbol, int256 newBasePrice, uint256 timestamp);
    event SimulationToggled(bool enabled);
    event VolatilityChanged(uint256 newBps);

    // ─────────────────────── Price management ────────────────────────────────

    /**
     * @notice Configura o actualiza el precio base para un símbolo.
     * @dev PERMISSIONLESS: cualquiera puede llamar esta función.
     *      En un contexto de producción esto sería un riesgo, pero en testnet
     *      es útil para que scripts de demo y keeper bots puedan actualizar precios.
     *
     *      Para cambiar los precios antes de un REDEPLOY, editar las constantes
     *      BTC_PRICE / ETH_PRICE en protocol/script/Deploy.s.sol — ese es el
     *      único lugar oficial donde tocar los precios iniciales.
     *
     * @param symbol  "BTC" o "ETH"
     * @param price   Precio con 8 decimales. Ejemplo: $66,000 → 66_000e8 = 6_600_000_000_000.
     */
    function setPrice(string calldata symbol, int256 price) external {
        // Almacena el precio base usando el hash del símbolo como clave.
        _basePrices[keccak256(bytes(symbol))] = price;
        emit PriceUpdated(symbol, price, block.timestamp);
    }

    // ─────────────────────── IFlashOracle ────────────────────────────────────

    /**
     * @notice Retorna el precio para el símbolo dado, con o sin ruido simulado.
     * @dev Implementa IFlashOracle.getPrice().
     *
     *      Cuando simulationEnabled = false:
     *        Retorna exactamente el precio configurado con setPrice().
     *        Ideal para tests: test.assertEq(price, BTC_REF) funciona exacto.
     *
     *      Cuando simulationEnabled = true:
     *        Agrega ruido determinista basado en block.timestamp y blockhash.
     *        El ruido es determinista (dado el mismo bloque, retorna el mismo precio),
     *        pero cambia cada bloque/30s.
     *
     * @param symbol "BTC" o "ETH"
     * @return Precio con 8 decimales. Si el símbolo no está configurado → retorna 0.
     */
    function getPrice(
        string calldata symbol
    ) external view override returns (int256) {
        bytes32 key = keccak256(bytes(symbol));
        int256 base = _basePrices[key];

        // Si no hay precio configurado para el símbolo, retorna 0.
        // FlashPredMarket debería validar esto, pero lo dejamos como señal de error.
        if (base == 0) return 0;

        // Sin simulación: precio exacto. Usado en tests unitarios.
        if (!simulationEnabled) return base;

        // ── COMPONENTE LENTO: tendencia que cambia cada 30 segundos ──────────
        //
        // Seed derivado del timestamp de la "ventana" de 30s actual y el símbolo.
        // Mismo seed durante 30s → mismo slowDev → precio se mantiene en esa dirección.
        // Asegura que openRound() y resolveRound() (60s después) vean precios distintos.
        //
        // seed % (2*vBps+1) → [0, 2*vBps]
        // − vBps            → [-vBps, +vBps]
        // × base / 10_000   → [-vBps% de base, +vBps% de base]
        uint256 slowSeed = uint256(
            keccak256(abi.encodePacked(block.timestamp / 30, key))
        );
        int256 vBps = int256(volatilityBps);
        int256 slowDev =
            (base * (int256(slowSeed % uint256(vBps * 2 + 1)) - vBps)) /
            10_000;

        // ── COMPONENTE RÁPIDO: ruido cosmético por bloque (~12s en Sepolia) ──
        //
        // Seed derivado del blockhash del bloque anterior (cambia cada bloque).
        // Rango muy pequeño (±0.02%) para no dominar sobre el componente lento.
        //
        // seed % 41 → [0, 40]
        // − 20      → [-20, +20]
        // × base / 100_000 → [-0.02% de base, +0.02% de base]
        uint256 fastSeed = uint256(
            keccak256(abi.encodePacked(blockhash(block.number - 1), key))
        );
        int256 fastDev = (base * (int256(fastSeed % 41) - 20)) / 100_000;

        // Precio final = base + tendencia lenta + ruido rápido
        return base + slowDev + fastDev;
    }

    /**
     * @notice Retorna el precio base puro, sin ruido de simulación.
     * @dev Útil para keeper bots o scripts que necesitan el precio "real" configurado,
     *      sin importar si la simulación está activa o no.
     *
     * @param symbol "BTC" o "ETH"
     * @return Precio base exacto con 8 decimales.
     */
    function getBasePrice(string calldata symbol) external view returns (int256) {
        return _basePrices[keccak256(bytes(symbol))];
    }

    // ─────────────────────── Simulation control ──────────────────────────────

    /**
     * @notice Activa el modo de simulación (precio con ruido pseudo-aleatorio).
     * @dev Llamado automáticamente por Deploy.s.sol después de deployar en Sepolia.
     *      Permissionless: cualquiera puede activarlo.
     */
    function enableSimulation() external {
        simulationEnabled = true;
        emit SimulationToggled(true);
    }

    /**
     * @notice Desactiva la simulación (vuelve a precio base exacto).
     * @dev Útil para fijar un precio específico en demos o debugging,
     *      sin necesidad de redesplegar el contrato.
     */
    function disableSimulation() external {
        simulationEnabled = false;
        emit SimulationToggled(false);
    }

    /**
     * @notice Ajusta la volatilidad máxima del ruido simulado.
     * @dev Default: 150 (±1.5%) — realista para BTC/ETH en 60-300s.
     *      Ejemplos:
     *       100 bps = ±1%   → movimientos suaves
     *       200 bps = ±2%   → movimientos normales
     *       500 bps = ±5%   → movimientos extremos (máximo permitido)
     *
     * @param bps Nuevo valor de volatilidad en basis points (máx 500).
     */
    function setVolatility(uint256 bps) external {
        if (bps > 500) revert MockFlashOracle__VolatilityTooHigh();
        volatilityBps = bps;
        emit VolatilityChanged(bps);
    }
}
