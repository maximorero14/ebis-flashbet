// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IAavePool.sol";
import "./FlashToken.sol";

/**
 * @title FlashVault
 * @dev Vault de colateral yield-bearing del protocolo FlashBet (Capa 1).
 *
 * ## ¿Qué hace?
 *  El vault actúa como intermediario entre el usuario y Aave V3:
 *   - El usuario deposita USDT → el vault lo presta en Aave → Aave paga interés.
 *   - El vault emite $FLASH 1:1 como recibo del depósito.
 *   - El usuario puede redimir $FLASH para recuperar su USDT en cualquier momento.
 *   - El interés acumulado queda "atrapado" en el vault (como aUSDT) hasta que
 *     alguien llame harvestYield(), que lo envía al Treasury en USDT.
 *
 * ## Flujo de tokens
 *
 *  DEPOSIT:
 *  Usuario ──[1000 USDT]──► Vault ──[supply 1000 USDT]──► Aave
 *                                ◄──[1050 aUSDT]──────────
 *  Usuario ◄──[1000 $FLASH]─── Vault
 *                                     totalDeposited = 1000
 *
 *  YIELD (automático, Aave acumula interés):
 *  aToken.balanceOf(vault) = 1000 + interés acumulado
 *  pendingYield = aBalance - totalDeposited
 *
 *  HARVEST:
 *  Vault ──[withdraw(yield)]──► Aave ──[USDT]──► Treasury
 *
 *  REDEEM:
 *  Usuario ──[500 $FLASH]──► burn ──► (destruidos)
 *  Vault ──[withdraw(500 USDT)]──► Aave ──[500 USDT]──► Usuario
 *                                    totalDeposited -= 500
 *
 * ## Invariante de solvencia
 *  totalDeposited <= aToken.balanceOf(vault)   (siempre, porque Aave acumula)
 *  Para cada usuario: si tiene X $FLASH, puede redimir exactamente X USDT.
 *
 * ## Por qué ReentrancyGuard
 *  En un ataque de reentrancy, un contrato malicioso llama recursivamente
 *  a redeem() antes de que la primera llamada termine. ReentrancyGuard
 *  agrega un mutex que bloquea llamadas anidadas al mismo contrato.
 *  Adicionalmente, seguimos Checks-Effects-Interactions en cada función:
 *  actualizar estado ANTES de llamar a contratos externos.
 *
 * ## Por qué forceApprove y no approve
 *  USDT tiene un bug conocido: si llamás approve(x) cuando ya hay allowance
 *  distinto de cero, la transacción revierte. SafeERC20.forceApprove hace
 *  approve(0) primero y luego approve(x), evitando el revert.
 */
contract FlashVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────── Immutables ──────────────────────────────────────
    //
    // Se fijan en el constructor y no pueden cambiar después.
    // Usar immutables para infraestructura crítica previene que un owner
    // malicioso pueda redirigir fondos cambiando el oracle o el treasury.

    FlashToken public immutable flashToken;   // El token $FLASH que este vault mintea/quema
    IERC20     public immutable usdt;         // USDT que el usuario deposita
    IAavePool  public immutable aavePool;     // Pool de Aave V3 donde se invierte el USDT
    IERC20     public immutable aToken;       // aUSDT: token de interés que Aave entrega al vault
    address    public immutable treasury;     // Dirección que recibe el yield cosechado

    // ─────────────────────── State ───────────────────────────────────────────

    /**
     * @notice USDT total depositado por usuarios (sin el yield acumulado).
     * @dev Se usa para calcular el yield pendiente:
     *      yield = aToken.balanceOf(vault) - totalDeposited
     *
     *      No incluye el yield porque Aave lo acumula automáticamente en el
     *      balance del aToken, pero nosotros solo trackeamos el principal.
     */
    uint256 public totalDeposited;

    // ─────────────────────── Custom errors ───────────────────────────────────

    error FlashVault__AmountZero();                // amount == 0
    error FlashVault__InsufficientFlashBalance();  // usuario no tiene suficiente $FLASH
    error FlashVault__NoYieldAvailable();          // aBalance <= totalDeposited (sin yield)
    error FlashVault__ZeroAddress();               // address(0) en constructor

    // ─────────────────────── Events ──────────────────────────────────────────

    event Deposited(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);
    event YieldHarvested(uint256 yieldAmount, address indexed treasury);

    // ─────────────────────── Constructor ─────────────────────────────────────

    /**
     * @notice Despliega el vault con sus dependencias inmutables.
     * @dev Después del despliegue, el script de deploy debe otorgar
     *      MINTER_ROLE y BURNER_ROLE a esta dirección en FlashToken.
     *      Sin esos roles, deposit() y redeem() revertirán.
     *
     * @param _flashToken  Dirección del contrato FlashToken desplegado.
     * @param _usdt        Dirección de USDT (6 decimales en Sepolia y mainnet).
     * @param _aavePool    Dirección del Pool proxy de Aave V3.
     * @param _aToken      Dirección del aToken de Aave correspondiente a USDT (aUSDT).
     * @param _treasury    Dirección que recibirá el yield y los fees.
     */
    constructor(
        address _flashToken,
        address _usdt,
        address _aavePool,
        address _aToken,
        address _treasury
    ) Ownable(msg.sender) {
        // Validamos que ninguna dirección sea address(0) antes de asignar.
        // Si una dirección es cero, el contrato quedaría inutilizable.
        if (
            _flashToken == address(0) ||
            _usdt       == address(0) ||
            _aavePool   == address(0) ||
            _aToken     == address(0) ||
            _treasury   == address(0)
        ) revert FlashVault__ZeroAddress();

        flashToken = FlashToken(_flashToken);
        usdt       = IERC20(_usdt);
        aavePool   = IAavePool(_aavePool);
        aToken     = IERC20(_aToken);
        treasury   = _treasury;
    }

    // ─────────────────────── Admin ────────────────────────────────────────────

    /**
     * @notice Pausa el vault. Bloquea deposit, redeem y harvestYield.
     * @dev Solo owner. Usar en emergencias (bug, exploit activo).
     */
    function pause() external onlyOwner { _pause(); }

    /**
     * @notice Reactiva el vault.
     * @dev Solo owner.
     */
    function unpause() external onlyOwner { _unpause(); }

    // ─────────────────────── Core functions ──────────────────────────────────

    /**
     * @notice Deposita USDT y recibe $FLASH 1:1.
     * @dev PRE-REQUISITO: el usuario debe haber aprobado este contrato para
     *      al menos `amount` USDT con: USDT.approve(vault, amount).
     *
     * Pasos internos:
     *  1. Tira USDT del usuario al vault (safeTransferFrom).
     *  2. Aprueba al pool de Aave para que tome el USDT (forceApprove).
     *  3. Suministra el USDT a Aave V3 → el vault recibe aUSDT.
     *  4. Registra el principal en totalDeposited.
     *  5. Acuña $FLASH 1:1 al usuario (requiere MINTER_ROLE en FlashToken).
     *
     * @param amount Cantidad de USDT a depositar (6 decimales).
     *               Ejemplo: 1_000_000 = 1 USDT.
     */
    function deposit(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert FlashVault__AmountZero();

        // 1. Tira USDT del usuario al vault.
        //    safeTransferFrom revierte si el usuario no aprobó suficiente.
        usdt.safeTransferFrom(msg.sender, address(this), amount);

        // 2. Aprueba al pool de Aave para tomar el USDT.
        //    forceApprove resuelve el quirk de USDT (approve a non-zero revierte).
        usdt.forceApprove(address(aavePool), amount);

        // 3. Suministra USDT a Aave. El vault recibe aUSDT (interest-bearing token).
        //    referralCode=0: no hay programa de referidos activo.
        aavePool.supply(address(usdt), amount, address(this), 0);

        // 4. Registra el principal depositado.
        //    aToken.balanceOf(vault) ahora > totalDeposited por el yield inicial del mock.
        totalDeposited += amount;

        // 5. Acuña $FLASH 1:1 al usuario.
        //    Requiere que este vault tenga MINTER_ROLE en FlashToken.
        flashToken.mint(msg.sender, amount);

        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Quema $FLASH del usuario y devuelve USDT 1:1.
     * @dev NO requiere approve previo de $FLASH al vault.
     *      El vault tiene BURNER_ROLE y puede quemar directamente.
     *
     * Pasos internos:
     *  1. Verifica saldo suficiente de $FLASH.
     *  2. Quema $FLASH del usuario (BURNER_ROLE en FlashToken).
     *  3. Reduce totalDeposited.
     *  4. Retira USDT de Aave directamente al usuario (no pasa por el vault).
     *
     * @param amount Cantidad de $FLASH a quemar / USDT a recibir (6 decimales).
     */
    function redeem(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert FlashVault__AmountZero();

        // Verifica que el usuario tenga suficiente $FLASH para quemar.
        if (flashToken.balanceOf(msg.sender) < amount) {
            revert FlashVault__InsufficientFlashBalance();
        }

        // 1. Quema $FLASH del usuario. Requiere BURNER_ROLE.
        //    _burn de OpenZeppelin reduce totalSupply y balance del usuario.
        flashToken.burn(msg.sender, amount);

        // 2. Reduce el principal registrado.
        //    CHECK: este -= nunca puede underflow porque verificamos balance arriba.
        totalDeposited -= amount;

        // 3. Retira USDT de Aave directamente al usuario.
        //    Aave quema los aUSDT del vault y envía USDT al usuario.
        //    La transferencia va directo al usuario sin pasar por el vault (gas eficiente).
        aavePool.withdraw(address(usdt), amount, msg.sender);

        emit Redeemed(msg.sender, amount);
    }

    /**
     * @notice Cosecha el interés acumulado de Aave y lo envía al Treasury.
     * @dev PERMISSIONLESS: cualquier cuenta puede llamar esta función.
     *      Los fondos SIEMPRE van al treasury hardcodeado (immutable), por lo que
     *      no hay vector de griefing — nadie puede redirigirlos.
     *
     * Lógica:
     *  aBalance = aToken.balanceOf(vault)    ← principal + interés acumulado
     *  yield    = aBalance - totalDeposited  ← solo el interés puro
     *  aavePool.withdraw(yield) → treasury   ← retira el interés al treasury
     *
     * Revierte si no hay yield (aBalance <= totalDeposited) para evitar
     * gastar gas en una transacción sin efecto.
     */
    function harvestYield() external whenNotPaused nonReentrant {
        // Lee el saldo actual de aUSDT del vault en Aave.
        // En Aave real, este balance crece por segundo (interés compuesto).
        // En el mock, crece porque supply() mintea amount + 5% desde el inicio.
        uint256 aBalance = aToken.balanceOf(address(this));

        // Si el saldo de aUSDT no supera el principal, no hay yield aún.
        if (aBalance <= totalDeposited) revert FlashVault__NoYieldAvailable();

        // El yield es la diferencia entre lo que tiene Aave y lo que depositamos.
        uint256 yield = aBalance - totalDeposited;

        // Retira el yield de Aave directamente al treasury (no pasa por el vault).
        // Nota: NO reducimos totalDeposited porque el yield no era principal.
        aavePool.withdraw(address(usdt), yield, treasury);

        emit YieldHarvested(yield, treasury);
    }

    // ─────────────────────── View helpers ────────────────────────────────────

    /**
     * @notice Retorna el yield pendiente sin ejecutar ninguna transacción.
     * @dev El frontend (Admin Panel) usa esto para mostrar cuánto yield
     *      puede cosecharse ahora mismo sin gastar gas.
     *
     * @return yield USDT que se enviaría al treasury si se llamara harvestYield() ahora.
     *              0 si no hay yield acumulado aún.
     */
    function pendingYield() external view returns (uint256 yield) {
        uint256 aBalance = aToken.balanceOf(address(this));
        if (aBalance > totalDeposited) {
            yield = aBalance - totalDeposited;
        }
        // Si aBalance <= totalDeposited, retorna 0 implícitamente.
    }
}
