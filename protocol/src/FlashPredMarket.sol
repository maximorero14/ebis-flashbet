// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./FlashToken.sol";
import "./interfaces/IFlashOracle.sol";

/**
 * @title FlashPredMarket
 * @dev Mercado de predicción de dirección de precio (Capa 2 del protocolo FlashBet).
 *
 * ## ¿Qué hace?
 *  Los usuarios apuestan $FLASH a que BTC/USD o ETH/USD subirá (UP) o bajará (DOWN)
 *  durante el período de una ronda. Al resolver, los ganadores reciben un payout
 *  proporcional del pool total (losing side va a los winners).
 *
 * ## Modelo Polymarket-style
 *  - Precio de REFERENCIA: se fija al ABRIR la ronda (openRound).
 *  - Apuestas: se aceptan hasta el ÚLTIMO SEGUNDO de la ronda.
 *  - Precio FINAL: se lee al RESOLVER (resolveRound). Si final > referencia → UP gana.
 *  - No hay fase "cerrada" previa a la resolución — bets hasta el último segundo.
 *
 * ## Ciclo de vida
 *
 *  IDLE
 *   │
 *   │ openRound() [onlyOwner]
 *   │ → Lee oracle → referencePrice fijado
 *   │ → phase = Open
 *   ▼
 *  OPEN  ◄── placeBet() acepta apuestas (cualquiera)
 *   │         hasta que: block.timestamp >= openedAt + ROUND_DURATION
 *   │
 *   │ resolveRound() [onlyOwner, solo post-expiración]
 *   │ → Lee oracle → finalPrice
 *   │ → upWon = (finalPrice > referencePrice)
 *   │ → Snapshot en _resolvedRounds[marketId][roundId]
 *   │ → phase = Resolved
 *   ▼
 *  RESOLVED
 *   │
 *   │ claimPayout() [winners, en cualquier momento]
 *   │ → payout = (bet.amount * totalPool) / winningSide
 *   ▼
 *  (nueva ronda puede abrirse con openRound() → vuelve a IDLE/OPEN)
 *
 * ## Por qué onlyOwner para openRound y resolveRound
 *  Chainlink Automation fue evaluado pero descartado para esta versión:
 *  añade complejidad de registro de upkeep, costo de LINK, y un contrato
 *  adicional. En el TFM, el owner opera manualmente desde el Admin Panel.
 *  El modelo es análogo a Augur v1 o PancakeSwap Prediction.
 *
 * ## Fórmula de payout
 *  totalPool  = totalUp + totalDown   (neto, fees ya deducidos)
 *  payout_i   = bet_i * totalPool / winningSide
 *
 *  Invariante: sum(payouts) <= totalPool (no puede haber insolvencia)
 *  Caso borde: si solo un lado apostó → refund completo (no hay contraparte)
 *
 * ## Seguridad
 *  - nonReentrant en placeBet y claimPayout (transferencias ERC-20)
 *  - Checks-Effects-Interactions en claimPayout (bet.claimed = true ANTES de transfer)
 *  - SafeERC20 para todas las transferencias (envuelve return value de ERC-20)
 *  - Immutables para flash, oracle, treasury (no modificables post-deploy)
 */
contract FlashPredMarket is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────────── Types ───────────────────────────────────────

    /**
     * @dev Dirección de la apuesta: el usuario predice si el precio sube o baja.
     *      UP:   finalPrice > referencePrice
     *      DOWN: finalPrice <= referencePrice
     */
    enum Direction {
        UP,
        DOWN
    }

    /**
     * @dev Fase del ciclo de vida de una ronda.
     *      Idle:     Estado inicial o post-resolución. No hay ronda activa.
     *      Open:     Ronda abierta. Apuestas aceptadas. Precio referencia fijado.
     *      Resolved: Ronda cerrada. Payouts disponibles. Oracle leído por segunda vez.
     */
    enum RoundPhase {
        Idle,
        Open,
        Resolved
    }

    /**
     * @dev Datos de la ronda ACTIVA. Se sobrescribe en cada openRound().
     *      Por eso el snapshot _resolvedRounds es necesario para historial.
     */
    struct Round {
        uint256    id;             // Número correlativo (1, 2, 3, ...)
        uint256    openedAt;       // Timestamp de cuando se abrió la ronda
        int256     referencePrice; // Precio del oracle al abrir — punto de comparación
        int256     finalPrice;     // Precio del oracle al resolver — determina ganador
        uint256    totalUp;        // $FLASH neto acumulado en el lado UP (sin fee)
        uint256    totalDown;      // $FLASH neto acumulado en el lado DOWN (sin fee)
        RoundPhase phase;          // Estado actual de la ronda
        bool       upWon;          // True si UP ganó; False si DOWN ganó
    }

    /**
     * @dev Snapshot inmutable guardado cuando se resuelve una ronda.
     *      Sobrevive al próximo openRound() que sobrescribe `rounds[marketId]`.
     *      Es el que usa claimPayout() para verificar resultados históricos.
     */
    struct ResolvedRound {
        bool    resolved;    // True si esta ronda fue resuelta
        bool    upWon;       // Resultado: True=UP ganó, False=DOWN ganó
        uint256 totalUp;     // Pool UP neto al momento de la resolución
        uint256 totalDown;   // Pool DOWN neto al momento de la resolución
    }

    /**
     * @dev Apuesta de un usuario en una ronda específica.
     *      amount: ya es el neto (fee deducido al momento de apostar).
     *      claimed: evita doble-claim (pattern Checks-Effects).
     */
    struct Bet {
        uint256   amount;   // $FLASH apostados neto (fee ya deducido)
        Direction dir;      // Dirección apostada: UP o DOWN
        bool      claimed;  // True si ya reclamó el payout
    }

    // ─────────────────────── Constants ───────────────────────────────────────

    /**
     * @notice Fee de trading en basis points. 100 bps = 1%.
     * @dev Se aplica en placeBet: fee = amount * 100 / 10_000 = 1%.
     *      El fee va al treasury en el mismo tx de la apuesta.
     */
    uint256 public constant FEE_BPS = 100;

    // IDs de mercados disponibles (extensible si se agregan más en el futuro)
    uint8 public constant MARKET_BTC   = 0;   // BTC/USD
    uint8 public constant MARKET_ETH   = 1;   // ETH/USD
    uint8 public constant MARKET_COUNT = 2;   // Total de mercados válidos

    // ─────────────────────── Immutables ──────────────────────────────────────
    //
    // Fijados en el constructor. No pueden cambiar post-deploy.
    // Esto garantiza que ni el owner puede redirigir fees o cambiar el oracle.

    /**
     * @notice Duración de cada ronda en segundos.
     * @dev 0 en el constructor → usa 300s por defecto.
     *      Para testnet/demo se usa 60s (configurable en Deploy.s.sol).
     */
    uint256 public immutable ROUND_DURATION;

    FlashToken   public immutable flashToken;  // Token con el que se apuesta
    IFlashOracle public immutable oracle;      // Oracle de precios (Chainlink o mock)
    address      public immutable treasury;    // Recibe el 1% de fee de cada apuesta

    // ─────────────────────── State ───────────────────────────────────────────

    /**
     * @notice Ronda activa por mercado. Solo guarda UNA ronda por mercado.
     * @dev Se sobrescribe en cada openRound(). Los resultados históricos
     *      están en _resolvedRounds, no aquí.
     */
    mapping(uint8 => Round) public rounds;

    /**
     * @notice Total de rondas que se han abierto por mercado (contador).
     * @dev Sirve como ID incremental: la ronda 1 tiene roundId=1, etc.
     */
    mapping(uint8 => uint256) public roundCount;

    /**
     * @notice Snapshots de rondas resueltas. marketId → roundId → snapshot.
     * @dev Private porque se accede solo via getResolvedRound() y claimPayout().
     *      Persiste indefinidamente — los usuarios pueden reclamar payouts
     *      de rondas antiguas aunque ya haya 10 rondas nuevas abiertas.
     */
    mapping(uint8 => mapping(uint256 => ResolvedRound)) private _resolvedRounds;

    /**
     * @notice Apuestas de cada usuario. marketId → roundId → bettor → Bet.
     * @dev Public para que el frontend pueda consultar si un usuario ya apostó
     *      y en qué dirección, sin necesitar un evento.
     */
    mapping(uint8 => mapping(uint256 => mapping(address => Bet))) public bets;

    /**
     * @dev Símbolo del oracle por market ID. "BTC" para market 0, "ETH" para 1.
     *      Se usa para llamar oracle.getPrice("BTC") o oracle.getPrice("ETH").
     */
    string[2] private _marketSymbols;

    // ─────────────────────── Custom errors ───────────────────────────────────
    //
    // Custom errors en lugar de require strings → ahorra gas en cada revert.
    // El frontend los captura y muestra mensajes en español.

    error FlashPredMarket__InvalidMarket();      // marketId >= MARKET_COUNT
    error FlashPredMarket__RoundNotIdle();       // openRound cuando ronda ya está Open
    error FlashPredMarket__RoundNotOpen();       // placeBet/resolve cuando no hay ronda Open
    error FlashPredMarket__RoundNotResolved();   // claimPayout antes de que se resuelva
    error FlashPredMarket__RoundStillOpen();     // resolveRound antes de que expire
    error FlashPredMarket__AmountZero();         // placeBet con amount=0
    error FlashPredMarket__BetWindowClosed();    // placeBet cuando el tiempo de ronda venció
    error FlashPredMarket__AlreadyClaimed();     // claimPayout doble
    error FlashPredMarket__NotWinner();          // claimPayout del lado perdedor
    error FlashPredMarket__NoBetFound();         // claimPayout sin haber apostado
    error FlashPredMarket__ZeroAddress();        // Constructor con address(0)
    error FlashPredMarket__DirectionConflict();  // Apostar UP y DOWN en la misma ronda
    error FlashPredMarket__AlreadyBet();         // Edge case: segunda apuesta post-cierre

    // ─────────────────────── Events ──────────────────────────────────────────
    //
    // Todos los eventos son indexados por The Graph (subgraph/).
    // Los parámetros `indexed` permiten filtrar por marketId, roundId, bettor, etc.

    event RoundOpened(
        uint8   indexed marketId,
        uint256 indexed roundId,
        uint256 openedAt,
        int256  referencePrice   // Precio fijado como punto de comparación
    );

    event BetPlaced(
        uint8   indexed marketId,
        uint256 indexed roundId,
        address indexed bettor,
        Direction dir,
        uint256 netAmount,       // Monto neto (fee ya deducido)
        uint256 fee              // Fee enviado al treasury
    );

    event RoundResolved(
        uint8   indexed marketId,
        uint256 indexed roundId,
        bool    upWon,
        int256  referencePrice,
        int256  finalPrice,
        uint256 totalPool,
        uint256 closedAt
    );

    event PayoutClaimed(
        uint8   indexed marketId,
        uint256 indexed roundId,
        address indexed user,
        uint256 amount           // $FLASH transferidos al ganador
    );

    // ─────────────────────── Constructor ─────────────────────────────────────

    /**
     * @notice Despliega el mercado de predicción.
     * @param _flashToken     Contrato FlashToken (token de apuesta).
     * @param _oracle         Oracle de precios (FlashOracle o MockFlashOracle).
     * @param _treasury       Recibe el 1% de fee de cada apuesta.
     * @param _owner          Owner del contrato (puede openRound, resolveRound, pause).
     * @param _roundDuration  Duración de ronda en segundos. 0 → usa 300s por defecto.
     */
    constructor(
        address _flashToken,
        address _oracle,
        address _treasury,
        address _owner,
        uint256 _roundDuration
    ) Ownable(_owner) {
        // Validación: ninguna dirección puede ser cero.
        if (
            _flashToken == address(0) ||
            _oracle     == address(0) ||
            _treasury   == address(0) ||
            _owner      == address(0)
        ) revert FlashPredMarket__ZeroAddress();

        flashToken = FlashToken(_flashToken);
        oracle     = IFlashOracle(_oracle);
        treasury   = _treasury;

        // Si se pasa 0, usar 300 segundos (5 minutos). Para demos se puede pasar 60.
        ROUND_DURATION = _roundDuration == 0 ? 300 : _roundDuration;

        // Mapear IDs a símbolos de oracle
        _marketSymbols[MARKET_BTC] = "BTC";
        _marketSymbols[MARKET_ETH] = "ETH";
    }

    // ─────────────────────── Admin ────────────────────────────────────────────

    /**
     * @notice Pausa todas las acciones del mercado. Solo owner.
     * @dev En emergencia: bloquea openRound, placeBet, resolveRound, claimPayout.
     */
    function pause() external onlyOwner { _pause(); }

    /**
     * @notice Reactiva el mercado. Solo owner.
     */
    function unpause() external onlyOwner { _unpause(); }

    // ───────────────────── Round lifecycle ───────────────────────────────────

    /**
     * @notice Abre una nueva ronda para `marketId` y fija el precio de referencia.
     * @dev SOLO el owner puede llamar esta función.
     *      El precio se fija en este momento (no al cerrar) — estilo Polymarket.
     *      Los usuarios conocen el precio de referencia desde que empieza a apostar.
     *
     * Pasos:
     *  1. Valida que el mercado sea BTC(0) o ETH(1).
     *  2. Verifica que la fase actual sea Idle o Resolved (no Open).
     *  3. Lee el precio actual del oracle → referencePrice.
     *  4. Incrementa roundCount y crea la nueva Round con phase=Open.
     *
     * @param marketId 0=BTC/USD, 1=ETH/USD.
     */
    function openRound(uint8 marketId) external onlyOwner whenNotPaused {
        _requireValidMarket(marketId);

        Round storage r = rounds[marketId];

        // No se puede abrir una ronda si ya hay una abierta (phase=Open).
        // Sí se puede abrir si está Idle (primera ronda) o Resolved (después de resolución).
        if (r.phase != RoundPhase.Idle && r.phase != RoundPhase.Resolved) {
            revert FlashPredMarket__RoundNotIdle();
        }

        // Lee el precio del oracle en este momento exacto.
        // Este precio es el punto de comparación: si el precio final > este, UP gana.
        int256 refPrice = oracle.getPrice(_marketSymbols[marketId]);

        // Incrementa el contador y usa ese valor como ID de la nueva ronda.
        uint256 newId = ++roundCount[marketId];

        // Sobrescribe el struct de la ronda activa con los datos nuevos.
        // Los datos de la ronda anterior ya fueron guardados en _resolvedRounds.
        rounds[marketId] = Round({
            id:             newId,
            openedAt:       block.timestamp,
            referencePrice: refPrice,
            finalPrice:     0,          // Se llenará en resolveRound
            totalUp:        0,          // Pool UP vacío al inicio
            totalDown:      0,          // Pool DOWN vacío al inicio
            phase:          RoundPhase.Open,
            upWon:          false       // Se determinará en resolveRound
        });

        emit RoundOpened(marketId, newId, block.timestamp, refPrice);
    }

    /**
     * @notice Coloca una apuesta en la ronda activa del mercado.
     * @dev Cualquier usuario puede llamar esta función mientras la ronda esté Open
     *      y no haya vencido (block.timestamp < openedAt + ROUND_DURATION).
     *
     * PRE-REQUISITO: el usuario debe haber aprobado este contrato para `amount` $FLASH:
     *   FlashToken.approve(FlashPredMarket, amount)
     *
     * Flujo del fee:
     *   1% del amount → treasury (inmediatamente, en este mismo tx)
     *   99% del amount → pool UP o DOWN (queda en el contrato)
     *
     * Un usuario puede apostar múltiples veces en la misma dirección (se acumula).
     * NO puede apostar en ambas direcciones en la misma ronda (DirectionConflict).
     *
     * @param marketId 0=BTC/USD, 1=ETH/USD.
     * @param dir      Direction.UP o Direction.DOWN.
     * @param amount   $FLASH brutos a apostar (6 decimales). Net = amount - 1%.
     */
    function placeBet(
        uint8 marketId,
        Direction dir,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        _requireValidMarket(marketId);
        if (amount == 0) revert FlashPredMarket__AmountZero();

        Round storage r = rounds[marketId];

        // La ronda debe estar en fase Open para aceptar apuestas.
        if (r.phase != RoundPhase.Open) revert FlashPredMarket__RoundNotOpen();

        // El tiempo de la ronda debe no haber vencido aún.
        // Se aceptan apuestas hasta el ÚLTIMO SEGUNDO (< en lugar de <=).
        if (block.timestamp >= r.openedAt + ROUND_DURATION) {
            revert FlashPredMarket__BetWindowClosed();
        }

        // Tira los $FLASH brutos del usuario al contrato.
        // El contrato actúa como "banca" que guarda todo el pool.
        IERC20(address(flashToken)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        // Calcula el fee (1%) y el monto neto que va al pool.
        uint256 fee       = (amount * FEE_BPS) / 10_000;  // 100/10000 = 1%
        uint256 netAmount = amount - fee;

        // Envía el fee al treasury inmediatamente.
        // El fee es en $FLASH (no en USDT). El treasury acumula ambos.
        if (fee > 0) {
            IERC20(address(flashToken)).safeTransfer(treasury, fee);
        }

        // Acumula el neto en el pool correspondiente.
        if (dir == Direction.UP) {
            r.totalUp += netAmount;
        } else {
            r.totalDown += netAmount;
        }

        // Verifica la apuesta existente del usuario en esta ronda.
        Bet storage existing = bets[marketId][r.id][msg.sender];

        if (existing.amount > 0) {
            // El usuario ya apostó en esta ronda.
            // Si apostó en la MISMA dirección: acumula el monto (OK).
            // Si apostó en dirección CONTRARIA: revierte (DirectionConflict).
            if (existing.dir != dir) revert FlashPredMarket__DirectionConflict();
            // Acumula la apuesta en la misma dirección.
            existing.amount += netAmount;
        } else {
            // Primera apuesta de este usuario en esta ronda → crea el registro.
            bets[marketId][r.id][msg.sender] = Bet({
                amount:  netAmount,
                dir:     dir,
                claimed: false
            });
        }

        emit BetPlaced(marketId, r.id, msg.sender, dir, netAmount, fee);
    }

    /**
     * @notice Resuelve la ronda del mercado, determina el ganador y guarda snapshot.
     * @dev SOLO el owner puede llamar. Solo cuando ROUND_DURATION ha transcurrido.
     *
     * Pasos:
     *  1. Verifica que la ronda esté Open y que haya vencido.
     *  2. Lee el precio FINAL del oracle.
     *  3. Determina upWon = (finalPrice > referencePrice).
     *  4. Cambia phase a Resolved.
     *  5. Guarda snapshot en _resolvedRounds (persiste aunque abra nueva ronda).
     *
     * Por qué snapshot: rounds[marketId] se sobrescribirá en el próximo openRound().
     * El snapshot en _resolvedRounds permite que claimPayout() funcione para rondas
     * históricas indefinidamente.
     *
     * @param marketId 0=BTC/USD, 1=ETH/USD.
     */
    function resolveRound(uint8 marketId) external onlyOwner whenNotPaused {
        _requireValidMarket(marketId);

        Round storage r = rounds[marketId];

        // Solo se puede resolver una ronda que esté Open.
        if (r.phase != RoundPhase.Open) revert FlashPredMarket__RoundNotOpen();

        // No se puede resolver antes de que expire el tiempo de la ronda.
        // Esto garantiza que todos los usuarios tuvieron tiempo de apostar.
        if (block.timestamp < r.openedAt + ROUND_DURATION)
            revert FlashPredMarket__RoundStillOpen();

        // Lee el precio FINAL del oracle en este momento.
        // Se compara con referencePrice para determinar el ganador.
        int256 finalP  = oracle.getPrice(_marketSymbols[marketId]);
        r.finalPrice   = finalP;

        // UP gana si el precio SUBIÓ respecto al precio de referencia.
        // DOWN gana si el precio BAJÓ o se mantuvo igual (<=).
        r.upWon = (finalP > r.referencePrice);

        // Cambia la fase a Resolved. Desde aquí, claimPayout() está disponible.
        r.phase = RoundPhase.Resolved;

        // Guarda el snapshot ANTES de que el próximo openRound() sobrescriba
        // rounds[marketId]. Este snapshot vive en _resolvedRounds indefinidamente.
        _resolvedRounds[marketId][r.id] = ResolvedRound({
            resolved:  true,
            upWon:     r.upWon,
            totalUp:   r.totalUp,
            totalDown: r.totalDown
        });

        emit RoundResolved(
            marketId,
            r.id,
            r.upWon,
            r.referencePrice,
            finalP,
            r.totalUp + r.totalDown,   // totalPool emitido para que el frontend lo muestre
            block.timestamp
        );
    }

    /**
     * @notice Reclama el payout del ganador para una ronda ya resuelta.
     * @dev Puede llamarse en cualquier momento después de que la ronda esté Resolved.
     *      Funciona aunque haya una nueva ronda abierta (usa snapshot histórico).
     *
     * Fórmula:
     *   totalPool  = totalUp + totalDown
     *   winningSide = upWon ? totalUp : totalDown
     *   payout     = (bet.amount * totalPool) / winningSide
     *
     * Caso especial (ronda sin contraparte):
     *   Si totalPool == winningSide → todos apostaron en el mismo lado.
     *   No hay ganancias: el ganador recibe de vuelta exactamente su apuesta neta.
     *
     * Seguridad — Checks-Effects-Interactions:
     *   bet.claimed = true  ← EFFECT (antes de cualquier transferencia)
     *   safeTransfer(...)   ← INTERACTION (al final)
     *   Esto previene ataques de reentrancy donde el atacante llame
     *   claimPayout() recursivamente antes de que claimed sea true.
     *
     * @param marketId 0=BTC/USD, 1=ETH/USD.
     * @param roundId  ID de la ronda de la que reclamar (puede ser histórica).
     */
    function claimPayout(
        uint8 marketId,
        uint256 roundId
    ) external whenNotPaused nonReentrant {
        _requireValidMarket(marketId);

        // Lee el snapshot histórico de la ronda (no la ronda activa).
        ResolvedRound storage rr = _resolvedRounds[marketId][roundId];

        // La ronda debe estar marcada como resuelta en el snapshot.
        if (!rr.resolved) revert FlashPredMarket__RoundNotResolved();

        // Lee la apuesta del usuario que llama.
        Bet storage bet = bets[marketId][roundId][msg.sender];

        // El usuario debe haber apostado en esta ronda.
        if (bet.amount == 0) revert FlashPredMarket__NoBetFound();

        // No se puede reclamar dos veces.
        if (bet.claimed) revert FlashPredMarket__AlreadyClaimed();

        // Verifica que el usuario esté del lado ganador.
        bool isWinner =
            (rr.upWon  && bet.dir == Direction.UP) ||   // UP ganó y apostó UP
            (!rr.upWon && bet.dir == Direction.DOWN);    // DOWN ganó y apostó DOWN

        if (!isWinner) revert FlashPredMarket__NotWinner();

        // Calcula el pool total y el lado ganador.
        uint256 totalPool   = rr.totalUp + rr.totalDown;
        uint256 winningSide = rr.upWon ? rr.totalUp : rr.totalDown;

        uint256 payout;
        if (totalPool == winningSide) {
            // Caso borde: nadie apostó en el lado contrario.
            // No hay ganancias → devolver monto neto exacto.
            payout = bet.amount;
        } else {
            // Caso normal: payout proporcional a la contribución al pool ganador.
            // Ejemplo: aposté 100 de 400 UP, totalPool=600 → payout = 100*600/400 = 150
            payout = (bet.amount * totalPool) / winningSide;
        }

        // EFFECT: marcar como reclamado ANTES de transferir (previene reentrancy).
        bet.claimed = true;

        // INTERACTION: transferir payout al ganador.
        IERC20(address(flashToken)).safeTransfer(msg.sender, payout);

        emit PayoutClaimed(marketId, roundId, msg.sender, payout);
    }

    // ─────────────────────── View helpers ────────────────────────────────────

    /**
     * @notice Retorna los datos de la ronda ACTIVA del mercado.
     * @dev Útil para el frontend: mostrar precio referencia, pool UP/DOWN, countdown.
     *      La ronda activa puede estar en Idle, Open o Resolved.
     * @param marketId 0=BTC/USD, 1=ETH/USD.
     */
    function getRound(uint8 marketId) external view returns (Round memory) {
        _requireValidMarket(marketId);
        return rounds[marketId];
    }

    /**
     * @notice Retorna el snapshot histórico de una ronda ya resuelta.
     * @dev Usado por claimPayout() y por el frontend (HistoryPage).
     *      Disponible indefinidamente, aunque haya nuevas rondas abiertas.
     * @param marketId 0=BTC/USD, 1=ETH/USD.
     * @param roundId  ID de la ronda resuelta.
     */
    function getResolvedRound(
        uint8 marketId,
        uint256 roundId
    ) external view returns (ResolvedRound memory) {
        return _resolvedRounds[marketId][roundId];
    }

    /**
     * @notice Retorna la apuesta de `bettor` en una ronda específica.
     * @dev Útil para que el frontend muestre si el usuario ya apostó y en qué dirección.
     *      amount=0 significa que el usuario no apostó en esa ronda.
     * @param marketId 0=BTC/USD, 1=ETH/USD.
     * @param roundId  ID de la ronda.
     * @param bettor   Dirección del apostador.
     */
    function getBet(
        uint8 marketId,
        uint256 roundId,
        address bettor
    ) external view returns (Bet memory) {
        return bets[marketId][roundId][bettor];
    }

    /**
     * @notice Retorna el símbolo del oracle para un market ID.
     * @return "BTC" para marketId=0, "ETH" para marketId=1.
     */
    function marketSymbol(uint8 marketId) external view returns (string memory) {
        _requireValidMarket(marketId);
        return _marketSymbols[marketId];
    }

    // ─────────────────────── Internal ────────────────────────────────────────

    /**
     * @dev Valida que marketId sea un mercado soportado.
     *      Evita accesos fuera de bounds en arrays y mappings.
     *      Se llama al inicio de todas las funciones públicas.
     */
    function _requireValidMarket(uint8 marketId) internal pure {
        if (marketId >= MARKET_COUNT) revert FlashPredMarket__InvalidMarket();
    }
}
