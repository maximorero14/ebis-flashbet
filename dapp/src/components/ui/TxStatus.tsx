/**
 * TxStatus — indicador de estado de una transacción blockchain.
 *
 * 3 estados visuales:
 *   1. pending   → "Confirmá en tu wallet" (spinner)
 *   2. confirming → "Procesando..." con link al tx en Etherscan
 *   3. success   → "Transacción confirmada ✔"
 *   4. error     → mensaje de error
 *
 * Todos los hashes de transacción son links a Sepolia Etherscan.
 */
import { shortHash }           from '../../utils/format'
import { parseContractError } from '../../utils/errors'

const ETHERSCAN_BASE = 'https://sepolia.etherscan.io/tx'

interface TxStatusProps {
  isPending:    boolean
  isConfirming: boolean
  isSuccess:    boolean
  hash?:        string
  error?:       Error | null
  label?:       string  // label opcional para diferenciar el tipo de tx
}

export function TxStatus({
  isPending,
  isConfirming,
  isSuccess,
  hash,
  error,
  label = 'Transacción',
}: TxStatusProps) {
  if (!isPending && !isConfirming && !isSuccess && !error) return null

  return (
    <div className="mt-3 rounded-lg border text-sm font-mono overflow-hidden">
      {/* Pendiente en wallet */}
      {isPending && (
        <div className="flex items-center gap-3 px-4 py-3 border-yellow-500/30 bg-yellow-500/5 text-yellow-400">
          <span className="inline-block w-4 h-4 border-2 border-yellow-400 border-t-transparent rounded-full animate-spin flex-shrink-0" />
          <span>Confirmá {label.toLowerCase()} en tu wallet...</span>
        </div>
      )}

      {/* Esperando confirmación on-chain */}
      {isConfirming && hash && (
        <div className="flex items-center gap-3 px-4 py-3 border-neon-cyan/30 bg-neon-cyan/5 text-neon-cyan">
          <span className="inline-block w-4 h-4 border-2 border-neon-cyan border-t-transparent rounded-full animate-spin flex-shrink-0" />
          <span>
            Procesando...{' '}
            <a
              href={`${ETHERSCAN_BASE}/${hash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="underline hover:text-white transition-colors"
            >
              {shortHash(hash)} ↗
            </a>
          </span>
        </div>
      )}

      {/* Éxito */}
      {isSuccess && hash && (
        <div className="flex items-center gap-3 px-4 py-3 border-green-500/30 bg-green-500/5 text-green-400">
          <span className="text-base">✔</span>
          <span>
            {label} confirmada —{' '}
            <a
              href={`${ETHERSCAN_BASE}/${hash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="underline hover:text-white transition-colors"
            >
              {shortHash(hash)} ↗
            </a>
          </span>
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="flex items-start gap-3 px-4 py-3 border-down/30 bg-down/5 text-down">
          <span className="text-base flex-shrink-0">✗</span>
          <span className="break-all text-xs">
            {parseContractError(error) ?? error.message}
          </span>
        </div>
      )}
    </div>
  )
}
