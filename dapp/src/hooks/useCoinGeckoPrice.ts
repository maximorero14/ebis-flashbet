/**
 * useCoinGeckoPrice — precio en tiempo real + datos históricos de CoinGecko.
 *
 * Usa la API pública gratuita de CoinGecko (sin API key requerida).
 * Refresca el precio cada 30s y el chart cada 5 minutos.
 *
 * NOTA: El precio mostrado en la DApp es solo de referencia visual.
 * El precio que determina el resultado de las rondas es el del
 * oracle Chainlink on-chain (MockFlashOracle en Sepolia).
 *
 * @param coinId  'bitcoin' | 'ethereum'
 */
import { useState, useEffect, useRef } from 'react'

export interface PricePoint {
  time:  number  // timestamp en ms
  price: number  // precio en USD
}

export interface CoinGeckoPriceData {
  currentPrice: number | null
  chartData:    PricePoint[]
  priceChange24h: number | null   // cambio porcentual en 24h
  isLoading:    boolean
  isError:      boolean
}

const COINGECKO_BASE = 'https://api.coingecko.com/api/v3'

// Cache en memoria para evitar re-fetches innecesarios entre renders
const priceCache = new Map<string, { price: number; change: number; ts: number }>()
const chartCache = new Map<string, { data: PricePoint[]; ts: number }>()

export function useCoinGeckoPrice(coinId: 'bitcoin' | 'ethereum'): CoinGeckoPriceData {
  const [currentPrice,   setCurrentPrice]   = useState<number | null>(null)
  const [chartData,      setChartData]      = useState<PricePoint[]>([])
  const [priceChange24h, setPriceChange24h] = useState<number | null>(null)
  const [isLoading,      setIsLoading]      = useState(true)
  const [isError,        setIsError]        = useState(false)

  // Ref para evitar updates en componente desmontado
  const mounted = useRef(true)
  useEffect(() => { mounted.current = true; return () => { mounted.current = false } }, [])

  useEffect(() => {
    let priceTimer: ReturnType<typeof setInterval>
    let chartTimer: ReturnType<typeof setInterval>

    /** Fetch precio actual + cambio 24h */
    const fetchPrice = async () => {
      // Usar cache si tiene menos de 25s
      const cached = priceCache.get(coinId)
      if (cached && Date.now() - cached.ts < 25_000) {
        if (mounted.current) {
          setCurrentPrice(cached.price)
          setPriceChange24h(cached.change)
          setIsError(false)
        }
        return
      }

      try {
        const res = await fetch(
          `${COINGECKO_BASE}/simple/price?ids=${coinId}&vs_currencies=usd&include_24hr_change=true`,
          { signal: AbortSignal.timeout(8000) }
        )
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const data = await res.json()

        const price  = data[coinId]?.usd            as number
        const change = data[coinId]?.usd_24h_change as number

        priceCache.set(coinId, { price, change, ts: Date.now() })

        if (mounted.current) {
          setCurrentPrice(price)
          setPriceChange24h(change)
          setIsError(false)
        }
      } catch {
        // No marcar error si ya tenemos precio — solo datos desactualizados
        if (mounted.current && currentPrice === null) setIsError(true)
      }
    }

    /** Fetch datos históricos (últimas 24h, granularidad automática ~hourly) */
    const fetchChart = async () => {
      // Usar cache si tiene menos de 4 minutos
      const cached = chartCache.get(coinId)
      if (cached && Date.now() - cached.ts < 4 * 60_000) {
        if (mounted.current) {
          setChartData(cached.data)
          setIsLoading(false)
        }
        return
      }

      try {
        const res = await fetch(
          `${COINGECKO_BASE}/coins/${coinId}/market_chart?vs_currency=usd&days=1`,
          { signal: AbortSignal.timeout(10_000) }
        )
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const data = await res.json()

        // CoinGecko devuelve array de [timestamp_ms, price]
        const points: PricePoint[] = (data.prices as [number, number][]).map(
          ([time, price]) => ({ time, price })
        )

        chartCache.set(coinId, { data: points, ts: Date.now() })

        if (mounted.current) {
          setChartData(points)
          setIsLoading(false)
        }
      } catch {
        if (mounted.current) {
          setIsLoading(false)
          if (chartData.length === 0) setIsError(true)
        }
      }
    }

    // Fetch inicial
    fetchPrice()
    fetchChart()

    // Intervalos de refresco
    priceTimer = setInterval(fetchPrice, 30_000)      // precio cada 30s
    chartTimer = setInterval(fetchChart, 5 * 60_000)  // chart cada 5 min

    return () => {
      clearInterval(priceTimer)
      clearInterval(chartTimer)
    }
  }, [coinId])

  return { currentPrice, chartData, priceChange24h, isLoading, isError }
}
