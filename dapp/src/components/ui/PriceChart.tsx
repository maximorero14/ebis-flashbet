/**
 * PriceChart — gráfico de precio en tiempo real al estilo Polymarket.
 *
 * Usa SOLO el stream de Binance WebSocket (gratuito, sin API key).
 * El gráfico muestra únicamente los últimos ~5 minutos de datos en vivo:
 *   - Eje Y ajustado al rango reciente → cada movimiento de $10-20 es visible
 *   - Se actualiza cada ~1 segundo (como Polymarket)
 *   - El cambio porcentual 24h viene también del stream de Binance (campo "P")
 *
 * Si la ronda está activa, dibuja una línea horizontal en el referencePrice
 * para que el usuario vea visualmente si el precio está "ganando" o "perdiendo".
 *
 * DISCLAIMER visible: el precio on-chain que determina el resultado
 * es el del oracle Chainlink, no el de Binance.
 *
 * Usa recharts (ya instalado en el proyecto).
 */
import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ReferenceLine,
  CartesianGrid,
} from 'recharts'
import { useLivePrice } from '../../hooks/useLivePrice'
import { formatPrice } from '../../utils/format'

interface PriceChartProps {
  /** 0 = BTC, 1 = ETH */
  marketId: 0 | 1
  /** Precio de referencia de la ronda (Chainlink, 8 decimales) — opcional */
  referencePrice?: bigint
  /** Si true la ronda está activa y se muestra la línea de referencia */
  showRefLine?: boolean
  /** Altura del gráfico en px (default 120) */
  chartHeight?: number
}

// Mapeo marketId → Binance / CoinGecko id
const COIN_IDS: Record<0 | 1, 'bitcoin' | 'ethereum'> = {
  0: 'bitcoin',
  1: 'ethereum',
}

/** Formatea timestamp ms a "HH:MM:SS" para ver el movimiento segundo a segundo */
function fmtTime(ts: number): string {
  return new Date(ts).toLocaleTimeString('es-AR', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  })
}

/** Tooltip personalizado */
function CustomTooltip({ active, payload }: any) {
  if (!active || !payload?.length) return null
  const point = payload[0]?.payload
  return (
    <div className="glass-card px-3 py-2 text-xs font-mono">
      <p className="text-slate-400">{fmtTime(point.time)}</p>
      <p className="text-white font-bold">${formatPrice(point.price)}</p>
    </div>
  )
}

export function PriceChart({ marketId, referencePrice, showRefLine = false, chartHeight = 120 }: PriceChartProps) {
  const coinId = COIN_IDS[marketId]

  // Solo Binance WS: precio en vivo + 24h% + puntos del gráfico
  const { livePoints, currentPrice, priceChange24h, isConnected } = useLivePrice(coinId)

  // Precio de referencia de la ronda en USD (Chainlink tiene 8 decimales)
  const refPriceUSD = referencePrice && referencePrice > 0n
    ? Number(referencePrice) / 1e8
    : null

  const isUp = priceChange24h !== null && priceChange24h >= 0

  return (
    <div className="space-y-2">
      {/* Precio actual + cambio 24h + indicador LIVE */}
      <div className="flex items-end justify-between">
        <div>
          {!currentPrice ? (
            <div className="h-7 w-28 bg-border/50 rounded animate-pulse" />
          ) : (
            <span className="font-mono text-xl font-bold text-white tabular-nums">
              ${formatPrice(currentPrice)}
            </span>
          )}
          {priceChange24h !== null && (
            <span className={`ml-2 text-xs font-mono font-bold ${isUp ? 'text-up' : 'text-down'}`}>
              {isUp ? '▲' : '▼'} {Math.abs(priceChange24h).toFixed(2)}% (24h)
            </span>
          )}
        </div>

        {/* Indicador LIVE */}
        <div className="flex flex-col items-end gap-0.5">
          <span className={`flex items-center gap-1 text-xs font-mono ${isConnected ? 'text-green-400' : 'text-slate-600'}`}>
            <span className={`w-1.5 h-1.5 rounded-full inline-block ${isConnected ? 'bg-green-400 animate-pulse' : 'bg-slate-600'}`} />
            {isConnected ? 'LIVE' : 'Connecting...'}
          </span>
          <span className="text-xs text-slate-600 font-mono">Binance WS</span>
        </div>
      </div>

      {/* Gráfico — solo datos en vivo de los últimos ~5 min */}
      {livePoints.length < 2 ? (
        <div style={{ height: chartHeight }} className="flex flex-col items-center justify-center gap-2">
          <span className="w-4 h-4 border-2 border-green-400 border-t-transparent rounded-full animate-spin" />
          <span className="text-xs text-slate-600 font-mono">
            {isConnected ? 'Recibiendo datos en vivo...' : 'Conectando a Binance...'}
          </span>
        </div>
      ) : (
        <ResponsiveContainer width="100%" height={chartHeight}>
          <LineChart data={livePoints} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
            <CartesianGrid
              strokeDasharray="3 3"
              stroke="rgba(255,255,255,0.03)"
              horizontal={true}
              vertical={false}
            />
            <XAxis
              dataKey="time"
              tickFormatter={fmtTime}
              tick={{ fontSize: 9, fill: '#475569', fontFamily: 'JetBrains Mono' }}
              tickLine={false}
              axisLine={false}
              interval="preserveStartEnd"
            />
            <YAxis
              domain={['auto', 'auto']}
              tick={{ fontSize: 9, fill: '#475569', fontFamily: 'JetBrains Mono' }}
              tickLine={false}
              axisLine={false}
              tickFormatter={v => `$${(v as number).toLocaleString('en-US', { maximumFractionDigits: 0 })}`}
              width={58}
            />
            <Tooltip content={<CustomTooltip />} />

            {/* Línea del precio de referencia de la ronda (Chainlink) */}
            {showRefLine && refPriceUSD !== null && (
              <ReferenceLine
                y={refPriceUSD}
                stroke="#a855f7"
                strokeDasharray="4 3"
                strokeWidth={1.5}
                label={{
                  value: `REF $${formatPrice(refPriceUSD)}`,
                  position: 'insideTopRight',
                  fontSize: 9,
                  fill: '#a855f7',
                  fontFamily: 'JetBrains Mono',
                }}
              />
            )}

            {/* Precio actual como línea punteada */}
            {currentPrice !== null && (
              <ReferenceLine
                y={currentPrice}
                stroke="#00f5ff"
                strokeDasharray="2 4"
                strokeWidth={1}
              />
            )}

            {/* Línea de precio en vivo — sin animación para updates en tiempo real */}
            <Line
              type="monotone"
              dataKey="price"
              stroke="#00f5ff"
              strokeWidth={1.5}
              dot={false}
              activeDot={{ r: 3, fill: '#00f5ff', strokeWidth: 0 }}
              isAnimationActive={false}
            />
          </LineChart>
        </ResponsiveContainer>
      )}

      {/* Disclaimer — importante para el TFM */}
      <div className="flex items-start gap-1.5 px-2 py-1.5 rounded bg-neon-purple/5 border border-neon-purple/10">
        <span className="text-neon-purple text-xs mt-0.5 flex-shrink-0">ℹ</span>
        <p className="text-xs text-slate-600 font-mono leading-relaxed">
          Precio visual vía Binance WS (referencia, últimos ~5 min). El resultado de cada ronda
          se determina con el oracle <span className="text-neon-purple">Chainlink</span> on-chain.
        </p>
      </div>
    </div>
  )
}
