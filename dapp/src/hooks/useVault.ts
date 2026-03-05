/**
 * useVault — hook principal para interactuar con FlashVault.
 *
 * Encapsula:
 *   - Balances (USDT del usuario, $FLASH del usuario, TVL del vault)
 *   - Allowances (USDT para FlashVault, $FLASH para FlashVault)
 *   - Escrituras: depositWithApprove, redeemWithApprove, harvestYield
 *
 * Flujo de un solo botón:
 *   - depositWithApprove(): approve USDT si es necesario → deposit
 *   - redeemWithApprove(): approve $FLASH si es necesario → redeem
 *   El usuario ve 1 o 2 popups en su wallet según el allowance actual.
 *
 * Reglas críticas:
 *   - deposit() requiere approve(FlashVault, amount) en USDT primero
 *   - redeem()  requiere approve(FlashVault, amount) en FlashToken primero
 *   - Ambos tokens tienen 6 decimales
 */
import {
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
  useAccount,
} from 'wagmi'
import { waitForTransactionReceipt } from '@wagmi/core'
import { sepolia }         from 'wagmi/chains'
import { useState }        from 'react'
import { CONTRACTS }       from '../config/contracts'
import { wagmiConfig }     from '../config/wagmi'
import { FlashVaultABI }   from '../abi/FlashVault'
import { FlashTokenABI }   from '../abi/FlashToken'
import { ERC20ABI }        from '../abi/ERC20'
import { parseFlash }      from '../utils/format'

const addr = CONTRACTS[sepolia.id]

/** Paso del flujo de tx secuencial para mostrar feedback en el botón */
export type VaultTxStep = 'idle' | 'approving' | 'acting'

export function useVault() {
  const { address, isConnected } = useAccount()

  // ── Estado local de la cantidad en el input ────────
  const [inputAmount, setInputAmount] = useState('')

  /** Paso actual del flujo de tx (idle → approving → acting) */
  const [txStep, setTxStep] = useState<VaultTxStep>('idle')

  // ── Reads en batch ─────────────────────────────────
  const {
    data: contractReads,
    refetch,
  } = useReadContracts({
    contracts: [
      // [0] TVL del vault
      {
        address:      addr.FlashVault,
        abi:          FlashVaultABI,
        functionName: 'totalDeposited',
      },
      // [1] Balance USDT del usuario
      {
        address:      addr.USDT,
        abi:          ERC20ABI,
        functionName: 'balanceOf',
        args:         address ? [address] : ['0x0000000000000000000000000000000000000000'],
      },
      // [2] Balance $FLASH del usuario
      {
        address:      addr.FlashToken,
        abi:          FlashTokenABI,
        functionName: 'balanceOf',
        args:         address ? [address] : ['0x0000000000000000000000000000000000000000'],
      },
      // [3] Allowance USDT → FlashVault
      {
        address:      addr.USDT,
        abi:          ERC20ABI,
        functionName: 'allowance',
        args:         address
          ? [address, addr.FlashVault]
          : ['0x0000000000000000000000000000000000000000', addr.FlashVault],
      },
      // [4] Allowance $FLASH → FlashVault
      {
        address:      addr.FlashToken,
        abi:          FlashTokenABI,
        functionName: 'allowance',
        args:         address
          ? [address, addr.FlashVault]
          : ['0x0000000000000000000000000000000000000000', addr.FlashVault],
      },
    ],
    query: {
      enabled:         isConnected && !!address,
      // Sin polling automático — se actualiza tras cada tx (isTxSuccess → refetch)
      // y en window focus (TanStack Query default). Vault no cambia sin acción del usuario.
      refetchInterval: false,
      staleTime:       30_000,
    },
  })

  const totalDeposited  = (contractReads?.[0]?.result as bigint | undefined) ?? 0n
  const usdtBalance     = (contractReads?.[1]?.result as bigint | undefined) ?? 0n
  const flashBalance    = (contractReads?.[2]?.result as bigint | undefined) ?? 0n
  const usdtAllowance   = (contractReads?.[3]?.result as bigint | undefined) ?? 0n
  const flashAllowance  = (contractReads?.[4]?.result as bigint | undefined) ?? 0n

  const parsedAmount = parseFlash(inputAmount)

  /** El usuario necesita aprobar USDT antes de depositar */
  const needsUSDTApproval  = parsedAmount > 0n && usdtAllowance < parsedAmount
  /** El usuario necesita aprobar $FLASH antes de redimir */
  const needsFLASHApproval = parsedAmount > 0n && flashAllowance < parsedAmount

  // ── Writes ─────────────────────────────────────────
  const {
    writeContract,
    writeContractAsync,
    data: txHash,
    isPending: isWritePending,
    reset: resetWrite,
    error: writeError,
  } = useWriteContract()

  const { isLoading: isTxConfirming, isSuccess: isTxSuccess } =
    useWaitForTransactionReceipt({ hash: txHash })

  /**
   * Depositar USDT → recibir $FLASH 1:1 con flujo de un solo botón.
   * Si el allowance es insuficiente, primero aprueba USDT y espera confirmación.
   */
  const depositWithApprove = async () => {
    if (parsedAmount === 0n) return
    try {
      if (usdtAllowance < parsedAmount) {
        setTxStep('approving')
        const approveHash = await writeContractAsync({
          address:      addr.USDT,
          abi:          ERC20ABI,
          functionName: 'approve',
          args:         [addr.FlashVault, parsedAmount],
        })
        // Esperar confirmación on-chain antes de depositar
        await waitForTransactionReceipt(wagmiConfig, { hash: approveHash })
      }

      setTxStep('acting')
      await writeContractAsync({
        address:      addr.FlashVault,
        abi:          FlashVaultABI,
        functionName: 'deposit',
        args:         [parsedAmount],
      })
    } catch {
      // No llamar resetWrite() — dejar que writeError quede visible al usuario
    } finally {
      setTxStep('idle')
    }
  }

  /**
   * Redimir $FLASH → recuperar USDT con flujo de un solo botón.
   * Si el allowance es insuficiente, primero aprueba $FLASH y espera confirmación.
   */
  const redeemWithApprove = async () => {
    if (parsedAmount === 0n) return
    try {
      if (flashAllowance < parsedAmount) {
        setTxStep('approving')
        const approveHash = await writeContractAsync({
          address:      addr.FlashToken,
          abi:          FlashTokenABI,
          functionName: 'approve',
          args:         [addr.FlashVault, parsedAmount],
        })
        await waitForTransactionReceipt(wagmiConfig, { hash: approveHash })
      }

      setTxStep('acting')
      await writeContractAsync({
        address:      addr.FlashVault,
        abi:          FlashVaultABI,
        functionName: 'redeem',
        args:         [parsedAmount],
      })
    } catch {
      // No llamar resetWrite() — dejar que writeError quede visible al usuario
    } finally {
      setTxStep('idle')
    }
  }

  /** Cosechar el yield acumulado en Aave y enviarlo al Treasury */
  const harvestYield = () =>
    writeContract({
      address:      addr.FlashVault,
      abi:          FlashVaultABI,
      functionName: 'harvestYield',
      args:         [],
    })

  return {
    // Datos del vault
    totalDeposited,
    usdtBalance,
    flashBalance,
    usdtAllowance,
    flashAllowance,

    // Input controlado
    inputAmount,
    setInputAmount,
    parsedAmount,

    // Flags de aprobación necesaria
    needsUSDTApproval,
    needsFLASHApproval,

    // Acciones (flujo de un solo botón)
    depositWithApprove,
    redeemWithApprove,
    harvestYield,

    // Estado de transacción
    txHash,
    txStep,
    isWritePending,
    isTxConfirming,
    isTxSuccess,
    writeError,
    resetWrite,

    // Refrescar datos
    refetch,
  }
}
