// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockAToken
 * @dev Simula el aToken de Aave (ej: aUSDT, aUSDC).
 *
 * ## ¿Qué es un aToken en Aave real?
 *  Cuando depositás 1000 USDT en Aave, recibís 1000 aUSDT.
 *  El balance de aUSDT crece automáticamente con el interés:
 *    balanceOf(user) = scaledBalance × liquidityIndex
 *  No necesitás hacer nada — solo holdear el aUSDT y crece.
 *  Al retirar, Aave quema el aUSDT y te devuelve USDT + interés.
 *
 * ## ¿Cómo lo simplifica este mock?
 *  Este MockAToken es un ERC-20 simple. El yield no crece automáticamente.
 *  En cambio, MockAavePool mintea más aTokens de los que corresponden al
 *  supply (5% extra), logrando el mismo efecto visible para FlashVault:
 *    aToken.balanceOf(vault) > totalDeposited → hay yield pendiente.
 *
 * ## Control de acceso: onlyPool
 *  Solo el MockAavePool puede mint y burn este token.
 *  Esto replica el comportamiento de Aave: el usuario nunca mintea aTokens
 *  directamente — siempre lo hace el pool en nombre del usuario.
 *  El modificador onlyPool evita que cualquier cuenta externa mintee
 *  o queme aTokens arbitrariamente.
 *
 * ## Decimales: 6 (igual que USDT)
 *  1 maUSDT = 1 USDT = 1,000,000 unidades (6 decimales).
 *  Consistente con todo el protocolo FlashBet.
 */
contract MockAToken is ERC20 {

    /**
     * @notice Dirección del MockAavePool que puede mint/burn este token.
     * @dev Inmutable: se fija en el constructor y no cambia.
     *      Solo el pool puede emitir o destruir estos tokens.
     */
    address public immutable pool;

    /**
     * @dev Restricción de acceso: solo el pool puede llamar las funciones marcadas.
     *      Análogo al modificador en el aToken real de Aave.
     */
    modifier onlyPool() {
        require(msg.sender == pool, "MockAToken: caller is not the pool");
        _;
    }

    /**
     * @notice Despliega el mock de aToken.
     * @dev El argumento `_underlying` no se usa en este mock (el pool ya lo sabe),
     *      pero se mantiene en la firma para compatibilidad con el constructor
     *      del MockAavePool que lo pasa.
     *
     * @dev  El primer argumento (token subyacente) no se usa en este mock — el pool ya lo sabe.
     * @param _pool     Dirección del MockAavePool, único autorizado a mint/burn.
     */
    constructor(
        address, // _underlying (no usado — el pool maneja la referencia al underlying)
        address _pool
    ) ERC20("Mock aUSDT", "maUSDT") {
        pool = _pool;
    }

    /**
     * @dev 6 decimales — igual que USDT. Override del default de ERC20 (18 dec).
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Acuña `amount` de maUSDT hacia `to`.
     * @dev Solo el pool puede llamar esto.
     *      Se llama en MockAavePool.supply() cuando el vault deposita USDT.
     *      El pool mintea amount + 5% para simular el yield instantáneo.
     *
     * @param to      Dirección que recibe los aTokens (FlashVault).
     * @param amount  Cantidad de aTokens a mintear (principal + 5% yield).
     */
    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
    }

    /**
     * @notice Quema `amount` de maUSDT desde `from`.
     * @dev Solo el pool puede llamar esto.
     *      Se llama en MockAavePool.withdraw() cuando el vault retira USDT.
     *      El pool quema los aTokens del vault antes de liberar el USDT.
     *
     * @param from    Dirección desde la que se queman los aTokens (FlashVault).
     * @param amount  Cantidad de aTokens a quemar.
     */
    function burn(address from, uint256 amount) external onlyPool {
        _burn(from, amount);
    }
}
