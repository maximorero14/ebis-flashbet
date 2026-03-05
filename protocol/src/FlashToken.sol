// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title FlashToken
 * @dev Token ERC-20 nativo del protocolo FlashBet. Símbolo: $FLASH.
 *
 * ## Rol en el protocolo
 *  $FLASH cumple DOS funciones:
 *   1. Recibo de depósito: el usuario deposita USDT en FlashVault y recibe
 *      $FLASH 1:1. Redimir $FLASH devuelve USDT (+ cualquier yield generado
 *      por Aave queda en el vault para distribuir vía harvestYield).
 *   2. Ficha de apuesta: $FLASH es el token con el que se apuesta en
 *      FlashPredMarket (UP o DOWN sobre BTC/USD, ETH/USD).
 *
 * ## Por qué AccessControl en lugar de Ownable
 *  Ownable tiene un único dueño que puede hacer todo. AccessControl permite
 *  asignar permisos granulares: FlashVault tiene MINTER + BURNER, pero no
 *  puede hacer pause. El admin puede pausar, pero no puede mint arbitrario.
 *  Esto minimiza el surface de ataque si una clave privada se compromete.
 *
 * ## Por qué BURNER_ROLE sin allowance
 *  En un ERC-20 estándar, para que A queme tokens de B, B debe hacer
 *  `approve(A, amount)` primero. En `redeem()`, el vault necesita quemar
 *  $FLASH del usuario en el mismo tx sin requerir una aprobación previa
 *  separada. BURNER_ROLE permite exactamente eso, de forma segura porque
 *  solo el vault (contrato auditado) tiene ese rol.
 *
 * ## Decimales: 6 (no 18)
 *  Tanto USDT como $FLASH usan 6 decimales. Esto hace que la contabilidad
 *  del vault sea limpia: 1_000_000 unidades = 1 USDT = 1 FLASH. No hay
 *  conversiones de escala entre los dos tokens.
 *
 * ## Custom errors vs require strings
 *  Los custom errors (`error FlashToken__AmountZero()`) gastan menos gas
 *  que `require(condition, "string")` porque no encodean el string en el
 *  calldata. Los errores también son más fáciles de capturar en el frontend.
 */
contract FlashToken is ERC20, AccessControl, Pausable {

    // ─────────────────────── Roles ───────────────────────────────────────────
    //
    // Los roles son hashes keccak256 de strings. Esto evita colisiones y
    // permite que cualquier contrato externo referencie el rol por nombre.
    //
    // MINTER_ROLE: asignado a FlashVault en Deploy.s.sol.
    //   Permite acuñar nuevos $FLASH. Solo el vault lo necesita (cuando el
    //   usuario deposita USDT).
    //
    // BURNER_ROLE: asignado a FlashVault en Deploy.s.sol.
    //   Permite destruir $FLASH de cualquier dirección sin allowance previo.
    //   Solo el vault lo necesita (cuando el usuario redime USDT).

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // ─────────────────────── Custom errors ───────────────────────────────────
    //
    // Se usan en lugar de require(..., "string") para ahorrar gas.
    // El frontend captura estos errores y los traduce a mensajes amigables.

    error FlashToken__AmountZero();          // amount == 0 en mint o burn
    error FlashToken__InvalidRecipient();    // to == address(0) en mint

    // ─────────────────────── Events ──────────────────────────────────────────
    //
    // Emitidos en cada operación importante. Los indexa The Graph y el frontend.

    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);

    // ─────────────────────── Constructor ─────────────────────────────────────

    /**
     * @notice Despliega FlashToken.
     * @dev Solo otorga DEFAULT_ADMIN_ROLE al deployer.
     *      MINTER_ROLE y BURNER_ROLE se otorgan explícitamente a FlashVault
     *      en Deploy.s.sol después del despliegue, manteniendo permisos
     *      mínimos por defecto.
     */
    constructor() ERC20("Flash Token", "FLASH") {
        // El deployer es administrador: puede gestionar roles y pausar.
        // NO tiene MINTER_ROLE ni BURNER_ROLE por defecto.
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ─────────────────────── Admin ────────────────────────────────────────────

    /**
     * @notice Pausa el contrato. Bloquea mint y burn.
     * @dev Solo DEFAULT_ADMIN_ROLE. Útil en caso de bug crítico o exploit.
     *      Cuando está pausado, `whenNotPaused` revierte en mint() y burn().
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }

    /**
     * @notice Reanuda el contrato. Reactiva mint y burn.
     * @dev Solo DEFAULT_ADMIN_ROLE.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    // ─────────────────────── Mint / Burn ─────────────────────────────────────

    /**
     * @notice Acuña `amount` $FLASH hacia `to`.
     * @dev Solo puede llamarlo una cuenta con MINTER_ROLE (FlashVault).
     *      Se llama internamente cuando el usuario hace deposit() en el vault.
     *      El amount es exactamente el mismo que el USDT depositado (6 dec).
     *
     * @param to      Dirección que recibe los tokens recién acuñados.
     * @param amount  Cantidad en micro-unidades FLASH (6 decimales).
     *                Ejemplo: 1_000_000 = 1 FLASH = 1 USDT.
     */
    function mint(address to, uint256 amount)
        external
        onlyRole(MINTER_ROLE)    // Solo FlashVault puede acuñar
        whenNotPaused            // Revierte si el contrato está pausado
    {
        // Validaciones básicas para evitar operaciones sin efecto
        if (amount == 0) revert FlashToken__AmountZero();
        if (to == address(0)) revert FlashToken__InvalidRecipient();

        // OpenZeppelin _mint: actualiza totalSupply y balance de `to`
        _mint(to, amount);

        emit TokensMinted(to, amount);
    }

    /**
     * @notice Destruye `amount` $FLASH de la dirección `from`.
     * @dev Solo puede llamarlo una cuenta con BURNER_ROLE (FlashVault).
     *      NO requiere allowance previo — el vault es de confianza.
     *      Se llama internamente cuando el usuario hace redeem() en el vault.
     *
     * @param from    Dirección cuyo $FLASH será quemado.
     * @param amount  Cantidad en micro-unidades FLASH (6 decimales).
     */
    function burn(address from, uint256 amount)
        external
        onlyRole(BURNER_ROLE)    // Solo FlashVault puede quemar
        whenNotPaused            // Revierte si el contrato está pausado
    {
        if (amount == 0) revert FlashToken__AmountZero();

        // OpenZeppelin _burn: reduce totalSupply y balance de `from`
        _burn(from, amount);

        emit TokensBurned(from, amount);
    }

    // ─────────────────────── ERC-20 overrides ────────────────────────────────

    /**
     * @dev Override de ERC20 para devolver 6 decimales en lugar de 18.
     *      Igual que USDT y USDC. Así: 1_000_000 unidades = 1 FLASH.
     *      Si usáramos 18 decimales, 1 FLASH = 1_000_000_000_000_000_000 unidades
     *      y la contabilidad con USDT (6 dec) sería complicada.
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
