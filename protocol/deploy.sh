#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Despliega FlashBet Protocol, actualiza dapp/.env.local
#             y redespliega el subgraph en Goldsky.
#
# Uso:
#   cd protocol
#   ./deploy.sh [--dry-run] [--skip-subgraph]
#
#   --dry-run        Solo muestra las addresses, no actualiza ningún archivo
#   --skip-subgraph  Salta el paso de Goldsky (solo contratos + .env.local)
#
# Requisitos:
#   - forge    (Foundry)
#   - jq       (para parsear el broadcast JSON)
#   - goldsky  (CLI de Goldsky: npm i -g @goldskycom/cli)
#   - .env     en el mismo directorio (copiado de .env.example)
#
# Variables opcionales en .env:
#   GOLDSKY_API_KEY     — si no estás logueado con `goldsky login`
#   SUBGRAPH_NAME       — nombre del subgraph en Goldsky (default: flashbet)
# =============================================================================

set -euo pipefail

CHAIN_ID=11155111
SCRIPT="script/Deploy.s.sol"
BROADCAST_JSON="broadcast/Deploy.s.sol/${CHAIN_ID}/run-latest.json"
DAPP_ENV="../dapp/.env.local"
SUBGRAPH_DIR="../subgraph"
SUBGRAPH_YAML="${SUBGRAPH_DIR}/subgraph.yaml"
DRY_RUN=false
SKIP_SUBGRAPH=false

# ── Flags ─────────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --dry-run)        DRY_RUN=true ;;
    --skip-subgraph)  SKIP_SUBGRAPH=true ;;
    *) echo "Uso: $0 [--dry-run] [--skip-subgraph]" >&2; exit 1 ;;
  esac
done

# ── Dependencias ──────────────────────────────────────────────────────────────
command -v forge &>/dev/null || { echo "Error: forge no encontrado. Instala Foundry." >&2; exit 1; }
command -v jq    &>/dev/null || { echo "Error: jq no encontrado. Instala jq." >&2; exit 1; }

if ! $DRY_RUN && ! $SKIP_SUBGRAPH; then
  command -v goldsky &>/dev/null || {
    echo "Error: goldsky CLI no encontrado." >&2
    echo "  Instalalo con: npm i -g @goldskycom/cli" >&2
    echo "  O saltá este paso con: ./deploy.sh --skip-subgraph" >&2
    exit 1
  }
fi

# ── Cargar variables de entorno del protocolo ─────────────────────────────────
if [[ ! -f .env ]]; then
  echo "Error: .env no encontrado en protocol/. Copia .env.example y rellena los valores." >&2
  exit 1
fi
set -a && source .env && set +a

# Nombre del subgraph en Goldsky (sobrescribible desde .env)
SUBGRAPH_NAME="${SUBGRAPH_NAME:-flashbet}"

# ── Deploy ────────────────────────────────────────────────────────────────────
echo ""
echo "================================================================="
echo "  FlashBet — Deploy a Sepolia (chainId ${CHAIN_ID})"
echo "================================================================="
echo ""

forge script "$SCRIPT" \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  -vvv

echo ""
echo "================================================================="
echo "  Extrayendo addresses del broadcast..."
echo "================================================================="
echo ""

if [[ ! -f "$BROADCAST_JSON" ]]; then
  echo "Error: broadcast JSON no encontrado en ${BROADCAST_JSON}" >&2
  echo "¿El deploy terminó correctamente?" >&2
  exit 1
fi

# Extrae la address de un contrato desplegado por nombre
extract_addr() {
  local name="$1"
  jq -r --arg name "$name" \
    '.transactions[] | select(.contractName == $name and .transactionType == "CREATE") | .contractAddress' \
    "$BROADCAST_JSON"
}

FLASHTOKEN=$(extract_addr "FlashToken")
FLASHVAULT=$(extract_addr "FlashVault")
FLASHPREDMARKET=$(extract_addr "FlashPredMarket")
TREASURY=$(extract_addr "Treasury")
MOCKORACLE=$(extract_addr "MockFlashOracle")
MOCKAAVEPOOL=$(extract_addr "MockAavePool")
MOCKATOKEN=$(extract_addr "MockAToken")

# Bloque del primer receipt del broadcast (hex → decimal, con buffer de 5)
START_BLOCK_HEX=$(jq -r '.receipts[0].blockNumber' "$BROADCAST_JSON")
START_BLOCK_DEC=$(printf '%d' "$START_BLOCK_HEX")
START_BLOCK=$((START_BLOCK_DEC > 5 ? START_BLOCK_DEC - 5 : 0))

# Validar que todas las addresses fueron encontradas
addresses_ok=true
for var in FLASHTOKEN FLASHVAULT FLASHPREDMARKET TREASURY MOCKORACLE MOCKAAVEPOOL MOCKATOKEN; do
  val="${!var}"
  if [[ -z "$val" || "$val" == "null" ]]; then
    echo "Error: no se encontró la address de ${var} en el broadcast JSON." >&2
    addresses_ok=false
  fi
done
$addresses_ok || exit 1

echo "  FlashToken (\$FLASH):   $FLASHTOKEN"
echo "  FlashVault:            $FLASHVAULT"
echo "  FlashPredMarket:       $FLASHPREDMARKET"
echo "  Treasury:              $TREASURY"
echo "  MockFlashOracle:       $MOCKORACLE"
echo "  MockAavePool:          $MOCKAAVEPOOL"
echo "  MockAToken (aUSDT):    $MOCKATOKEN"
echo "  Start block:           $START_BLOCK"
echo ""

# ── Dry-run: salir sin modificar nada ─────────────────────────────────────────
if $DRY_RUN; then
  echo "[--dry-run] No se actualizó ningún archivo."
  exit 0
fi

# ── Actualizar dapp/.env.local ────────────────────────────────────────────────
echo "================================================================="
echo "  Actualizando ${DAPP_ENV}..."
echo "================================================================="
echo ""

touch "$DAPP_ENV"

set_env_var() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$DAPP_ENV" 2>/dev/null; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$DAPP_ENV"
  else
    echo "${key}=${value}" >> "$DAPP_ENV"
  fi
}

set_env_var "VITE_FLASHTOKEN_ADDRESS"      "$FLASHTOKEN"
set_env_var "VITE_FLASHVAULT_ADDRESS"      "$FLASHVAULT"
set_env_var "VITE_FLASHPREDMARKET_ADDRESS" "$FLASHPREDMARKET"
set_env_var "VITE_TREASURY_ADDRESS"        "$TREASURY"
set_env_var "VITE_MOCKORACLE_ADDRESS"      "$MOCKORACLE"
set_env_var "VITE_MOCKAAVEPOOL_ADDRESS"    "$MOCKAAVEPOOL"
set_env_var "VITE_MOCKATOKEN_ADDRESS"      "$MOCKATOKEN"

echo "  Listo. ${DAPP_ENV} actualizado."
echo ""

# ── Subgraph — saltar si se pidió ─────────────────────────────────────────────
if $SKIP_SUBGRAPH; then
  echo "[--skip-subgraph] Saltando despliegue del subgraph."
  echo ""
  echo "  Próximos pasos:"
  echo "    cd ../dapp && npm run dev"
  echo ""
  exit 0
fi

# ── Actualizar subgraph.yaml con la nueva address y startBlock ───────────────
echo "================================================================="
echo "  Actualizando ${SUBGRAPH_YAML}..."
echo "================================================================="
echo ""

if [[ ! -f "$SUBGRAPH_YAML" ]]; then
  echo "Error: no se encontró ${SUBGRAPH_YAML}" >&2
  exit 1
fi

# Reemplaza address y startBlock del datasource FlashPredMarket
# macOS usa sed -i '' (BSD sed); Linux usa sed -i
SED_I="sed -i ''"
if [[ "$(uname)" == "Linux" ]]; then
  SED_I="sed -i"
fi

$SED_I "s|address: \"0x[0-9a-fA-F]*\"|address: \"${FLASHPREDMARKET}\"|" "$SUBGRAPH_YAML"
$SED_I "s|startBlock: [0-9]*|startBlock: ${START_BLOCK}|" "$SUBGRAPH_YAML"

echo "  address   → $FLASHPREDMARKET"
echo "  startBlock → $START_BLOCK"
echo ""

# ── Build del subgraph ────────────────────────────────────────────────────────
echo "================================================================="
echo "  Compilando subgraph (codegen + build)..."
echo "================================================================="
echo ""

pushd "$SUBGRAPH_DIR" > /dev/null

npm run codegen
npm run build

# ── Deploy a Goldsky ──────────────────────────────────────────────────────────
SUBGRAPH_VERSION="1.0.$(date +%Y%m%d%H%M)"

echo ""
echo "================================================================="
echo "  Desplegando a Goldsky — ${SUBGRAPH_NAME}/${SUBGRAPH_VERSION}"
echo "================================================================="
echo ""

# Si GOLDSKY_API_KEY está definido, pasarlo como variable de entorno
if [[ -n "${GOLDSKY_API_KEY:-}" ]]; then
  GOLDSKY_OUTPUT=$(GOLDSKY_API_KEY="$GOLDSKY_API_KEY" goldsky subgraph deploy "${SUBGRAPH_NAME}/${SUBGRAPH_VERSION}" --path . | tee /dev/tty)
else
  GOLDSKY_OUTPUT=$(goldsky subgraph deploy "${SUBGRAPH_NAME}/${SUBGRAPH_VERSION}" --path . | tee /dev/tty)
fi
GRAPH_URL=$(echo "$GOLDSKY_OUTPUT" | grep -o 'https://api\.goldsky\.com[^ ]*')

popd > /dev/null

# Actualizar VITE_GRAPH_URL automáticamente si se obtuvo la URL
if [[ -n "$GRAPH_URL" ]]; then
  set_env_var "VITE_GRAPH_URL" "$GRAPH_URL"
  echo "  VITE_GRAPH_URL → $GRAPH_URL"
  echo "  Listo. ${DAPP_ENV} actualizado con la nueva URL del subgraph."
  echo ""
fi

echo ""
echo "================================================================="
echo "  Deploy completo."
echo "================================================================="
echo ""
echo "  Subgraph: ${SUBGRAPH_NAME}/${SUBGRAPH_VERSION}"
echo ""
echo "  Próximo paso:"
echo "    cd ../dapp && npm run dev"
echo ""
