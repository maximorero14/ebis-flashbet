/**
 * useLivePrice — precio en tiempo real via Binance WebSocket.
 *
 * Usa el stream público de Binance (miniTicker) — completamente gratuito,
 * sin API key, actualiza cada ~1 segundo exactamente como Polymarket.
 *
 * Stream: wss://stream.binance.com:9443/ws/{symbol}@miniTicker
 * Payload clave:
 *   { c: "precio_actual", P: "variacion_24h_pct", o: "precio_apertura", ... }
 *
 * Mantiene una ventana deslizante de los últimos 300 puntos (~5 min a 1/seg).
 * El gráfico usa SOLO estos puntos — eje Y ajustado al rango reciente,
 * lo que hace que cada movimiento de $10-20 sea visualmente significativo.
 */
import { useState, useEffect, useRef } from 'react'
import type { PricePoint } from './useCoinGeckoPrice'

const BINANCE_WS = 'wss://stream.binance.com:9443/ws'

const SYMBOL_MAP: Record<'bitcoin' | 'ethereum', string> = {
  bitcoin:  'btcusdt',
  ethereum: 'ethusdt',
}

/** Máximo de puntos live en memoria (ventana deslizante ~5 min) */
const MAX_LIVE_POINTS = 300

export interface LivePriceData {
  livePoints:     PricePoint[]
  currentPrice:   number | null
  priceChange24h: number | null   // cambio % 24h desde Binance (campo "P")
  isConnected:    boolean
}

export function useLivePrice(coinId: 'bitcoin' | 'ethereum'): LivePriceData {
  const [livePoints,     setLivePoints]     = useState<PricePoint[]>([])
  const [currentPrice,   setCurrentPrice]   = useState<number | null>(null)
  const [priceChange24h, setPriceChange24h] = useState<number | null>(null)
  const [isConnected,    setIsConnected]    = useState(false)

  const wsRef   = useRef<WebSocket | null>(null)
  const mounted = useRef(true)

  useEffect(() => {
    mounted.current = true

    const symbol = SYMBOL_MAP[coinId]
    const url    = `${BINANCE_WS}/${symbol}@miniTicker`

    const connect = () => {
      const ws = new WebSocket(url)
      wsRef.current = ws

      ws.onopen = () => {
        if (mounted.current) setIsConnected(true)
      }

      ws.onmessage = (evt) => {
        if (!mounted.current) return
        try {
          const data  = JSON.parse(evt.data as string)
          const price = parseFloat(data.c)  // "c" = current close price
          if (isNaN(price) || price <= 0) return

          // "P" = price change percent en las últimas 24h (ej: "3.17")
          const changePct = parseFloat(data.P)
          if (!isNaN(changePct)) setPriceChange24h(changePct)

          const point: PricePoint = { time: Date.now(), price }

          setCurrentPrice(price)
          setLivePoints(prev => {
            const next = [...prev, point]
            // Ventana deslizante: descarta los más viejos
            return next.length > MAX_LIVE_POINTS
              ? next.slice(next.length - MAX_LIVE_POINTS)
              : next
          })
        } catch {
          // Silencioso — no romper la app si llega un mensaje malformado
        }
      }

      ws.onerror = () => {
        if (mounted.current) setIsConnected(false)
      }

      ws.onclose = () => {
        if (!mounted.current) return
        setIsConnected(false)
        // Reconectar después de 3s si el componente sigue montado
        setTimeout(() => {
          if (mounted.current) connect()
        }, 3_000)
      }
    }

    connect()

    return () => {
      mounted.current = false
      if (wsRef.current) {
        wsRef.current.onclose = null  // evitar reconexión en cleanup
        wsRef.current.close()
      }
    }
  }, [coinId])

  return { livePoints, currentPrice, priceChange24h, isConnected }
}
