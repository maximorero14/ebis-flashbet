/**
 * useRoundTimer — countdown en tiempo real para una ronda activa.
 *
 * Recibe el timestamp de apertura (openedAt) y la duración (roundDuration)
 * de una ronda, y retorna los segundos restantes actualizados cada segundo.
 *
 * @param openedAt       Timestamp Unix de apertura (en segundos, como bigint)
 * @param roundDuration  Duración total de la ronda en segundos (como bigint)
 * @returns              Segundos restantes (0 cuando la ronda expira)
 */
import { useState, useEffect } from 'react'

export function useRoundTimer(
  openedAt:      bigint | undefined,
  roundDuration: bigint | undefined,
): number {
  const [timeLeft, setTimeLeft] = useState(0)

  useEffect(() => {
    // Si no hay datos de ronda, no hay countdown
    if (!openedAt || !roundDuration) {
      setTimeLeft(0)
      return
    }

    const endTimestamp = Number(openedAt) + Number(roundDuration)

    const tick = () => {
      const remaining = endTimestamp - Math.floor(Date.now() / 1000)
      setTimeLeft(Math.max(0, remaining))
    }

    tick() // actualización inmediata sin esperar 1s

    const intervalId = setInterval(tick, 1000)
    return () => clearInterval(intervalId)
  }, [openedAt, roundDuration])

  return timeLeft
}
