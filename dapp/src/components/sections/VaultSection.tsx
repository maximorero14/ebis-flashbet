/**
 * VaultSection — interfaz para el FlashVault.
 *
 * Permite al usuario:
 *   DEPOSIT: USDT → $FLASH 1:1 (un botón — approve + deposit automático si es necesario)
 *   REDEEM:  $FLASH → USDT   (un botón — approve + redeem automático si es necesario)
 *   Harvest Yield: recolectar interés de Aave (acción de operador)
 *
 * Flujo de un solo botón:
 *   El usuario aprieta "Depositar" → si necesita approve, MetaMask muestra 2 popups
 *   (approve + deposit). Si el allowance ya es suficiente, solo 1 popup (deposit).
 *
 * Reglas del protocolo:
 *   - $FLASH y USDT tienen 6 decimales
 *   - deposit() requiere approve(FlashVault, amount) en USDT
 *   - redeem()  requiere approve(FlashVault, amount) en FlashToken
 */
import { useState, useEffect } from 'react'
import { useAccount }          from 'wagmi'
import { GlassCard }           from '../ui/GlassCard'
import { NeonButton }          from '../ui/NeonButton'
import { TxStatus }            from '../ui/TxStatus'
import { useVault }            from '../../hooks/useVault'
import { formatFlash }         from '../../utils/format'

type Tab = 'deposit' | 'redeem'

export function VaultSection() {
  const { isConnected } = useAccount()
  const [tab, setTab]   = useState<Tab>('deposit')

  const {
    totalDeposited, usdtBalance, flashBalance,
    inputAmount, setInputAmount, parsedAmount,
    needsUSDTApproval, needsFLASHApproval,
    depositWithApprove, redeemWithApprove,
    txHash, txStep, isWritePending, isTxConfirming, isTxSuccess, writeError, resetWrite,
    refetch,
  } = useVault()

  // Refrescar datos cuando la tx se confirma
  useEffect(() => {
    if (isTxSuccess) {
      setInputAmount('')
      refetch()
    }
  }, [isTxSuccess])

  // Resetear tx al cambiar de tab
  useEffect(() => {
    resetWrite()
    setInputAmount('')
  }, [tab])

  const balance       = tab === 'deposit' ? usdtBalance   : flashBalance
  const balanceSymbol = tab === 'deposit' ? 'USDT'        : 'FLASH'
  const outSymbol     = tab === 'deposit' ? 'FLASH'       : 'USDT'

  const setMax = () => setInputAmount(formatFlash(balance).replace(/,/g, ''))

  const isLoading = isWritePending || isTxConfirming || txStep !== 'idle'

  /**
   * Etiqueta contextual del botón según el paso del flujo de tx.
   * Muestra qué está pasando cuando hay dos transacciones en secuencia.
   */
  const stepLabel =
    txStep === 'approving' ? `Aprobando ${tab === 'deposit' ? 'USDT' : '$FLASH'}...` :
    txStep === 'acting'    ? (tab === 'deposit' ? 'Depositando...' : 'Retirando...') :
    null

  /** Indica si se necesita approve (para mostrar hint al usuario) */
  const needsApprove = tab === 'deposit' ? needsUSDTApproval : needsFLASHApproval

  /** Determina el botón de acción principal (un solo botón para toda la operación) */
  const renderActionButton = () => {
    if (tab === 'deposit') {
      return (
        <NeonButton
          variant="cyan"
          fullWidth
          loading={isLoading}
          onClick={depositWithApprove}
          disabled={parsedAmount === 0n || parsedAmount > usdtBalance}
        >
          {stepLabel ?? `Depositar ${inputAmount || '0'} USDT`}
          {needsApprove && !isLoading && (
            <span className="text-xs opacity-50 ml-1">(requiere approve)</span>
          )}
        </NeonButton>
      )
    }

    return (
      <NeonButton
        variant="cyan"
        fullWidth
        loading={isLoading}
        onClick={redeemWithApprove}
        disabled={parsedAmount === 0n || parsedAmount > flashBalance}
      >
        {stepLabel ?? `Retirar ${inputAmount || '0'} FLASH`}
        {needsApprove && !isLoading && (
          <span className="text-xs opacity-50 ml-1">(requiere approve)</span>
        )}
      </NeonButton>
    )
  }

  return (
    <GlassCard>
      {/* Header */}
      <div className="mb-5">
        <h2 className="font-orbitron text-lg font-bold text-white tracking-wider">
          ⬡ FLASH VAULT
        </h2>
        <p className="text-xs text-slate-500 font-mono mt-0.5">
          Deposit USDT → Get $FLASH
        </p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 gap-3 mb-5">
        <div className="rounded-lg bg-surface/50 border border-border/50 p-3">
          <p className="text-xs text-slate-500 font-mono uppercase tracking-wider">TVL</p>
          <p className="font-mono text-sm text-white mt-0.5">
            {formatFlash(totalDeposited)} <span className="text-slate-500">USDT</span>
          </p>
        </div>
        <div className="rounded-lg bg-surface/50 border border-border/50 p-3">
          <p className="text-xs text-slate-500 font-mono uppercase tracking-wider">Tu FLASH</p>
          <p className="font-mono text-sm text-neon-cyan mt-0.5">
            {formatFlash(flashBalance)}
          </p>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex rounded-lg overflow-hidden border border-border mb-5">
        {(['deposit', 'redeem'] as Tab[]).map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={[
              'flex-1 py-2 text-xs font-mono uppercase tracking-widest transition-colors',
              tab === t
                ? 'bg-neon-cyan/10 text-neon-cyan'
                : 'text-slate-500 hover:text-slate-300',
            ].join(' ')}
          >
            {t === 'deposit' ? '↓ Deposit' : '↑ Redeem'}
          </button>
        ))}
      </div>

      {/* Input */}
      {isConnected ? (
        <div className="space-y-4">
          <div>
            <div className="flex justify-between items-center mb-1.5">
              <label className="text-xs text-slate-500 font-mono uppercase tracking-wider">
                Amount ({balanceSymbol})
              </label>
              <span className="text-xs text-slate-600 font-mono">
                Balance: {formatFlash(balance)} {balanceSymbol}
              </span>
            </div>
            <div className="flex gap-2">
              <input
                type="number"
                min="0"
                step="0.000001"
                value={inputAmount}
                onChange={e => setInputAmount(e.target.value)}
                placeholder="0.00"
                className="flex-1 bg-surface border border-border rounded-lg px-3 py-2.5 font-mono text-sm text-white placeholder-slate-600 focus:outline-none focus:border-neon-cyan/50 transition-colors"
              />
              <button
                onClick={setMax}
                className="px-3 py-2 text-xs font-mono text-neon-cyan border border-neon-cyan/30 rounded-lg hover:bg-neon-cyan/10 transition-colors"
              >
                MAX
              </button>
            </div>
            {parsedAmount > 0n && parsedAmount > balance ? (
              <div className="flex items-center gap-2 mt-2 px-3 py-2 rounded-lg border border-down/40 bg-down/10 text-down text-xs font-mono">
                <span>✗</span>
                <span>
                  Saldo insuficiente — tenés{' '}
                  <span className="font-bold text-white">{formatFlash(balance)} {balanceSymbol}</span>{' '}
                  disponible
                </span>
              </div>
            ) : inputAmount ? (
              <p className="text-xs text-slate-600 font-mono mt-1">
                Recibirás: <span className="text-white">{inputAmount} {outSymbol}</span>
              </p>
            ) : null}
          </div>

          {renderActionButton()}

          <TxStatus
            isPending={isWritePending}
            isConfirming={isTxConfirming}
            isSuccess={isTxSuccess}
            hash={txHash}
            error={writeError}
            label={
              txStep === 'approving'
                ? `Aprobando ${tab === 'deposit' ? 'USDT' : '$FLASH'}`
                : tab === 'deposit' ? 'Depósito' : 'Retiro'
            }
          />
        </div>
      ) : (
        // Estado sin wallet
        <div className="flex flex-col items-center justify-center py-8 gap-3">
          <div className="w-12 h-12 rounded-full border-2 border-border/50 flex items-center justify-center text-xl">
            🔒
          </div>
          <p className="text-sm text-slate-500 font-mono">Conectá tu wallet para operar</p>
        </div>
      )}
    </GlassCard>
  )
}
