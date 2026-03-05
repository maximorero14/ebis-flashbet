/**
 * chunkedGetLogs — helper para RPCs con límite de block range.
 *
 * Divide el rango [fromBlock, toBlock] en chunks de `chunkSize` bloques,
 * hace las requests en paralelo (por lotes) y concatena los resultados.
 *
 * Uso ejemplo:
 *   const logs = await chunkedGetLogs(publicClient, {
 *     address, event, args,
 *     fromBlock: 7_800_000n,
 *     toBlock: 'latest',
 *     chunkSize: 2_000n,
 *   })
 */
import { type PublicClient, type GetLogsParameters } from 'viem'

interface ChunkedGetLogsOptions extends Omit<GetLogsParameters, 'fromBlock' | 'toBlock'> {
    fromBlock: bigint
    toBlock?: bigint | 'latest'
    /** Tamaño de cada chunk en bloques. Default: 2000. */
    chunkSize?: bigint
}

export async function chunkedGetLogs(
    client: PublicClient,
    options: ChunkedGetLogsOptions,
): Promise<Awaited<ReturnType<PublicClient['getLogs']>>> {
    const { chunkSize = 2_000n, fromBlock, toBlock: rawTo, ...rest } = options

    // Resolver "latest" al número de bloque actual
    const toBlock =
        rawTo === 'latest' || rawTo === undefined
            ? await client.getBlockNumber()
            : rawTo

    const allLogs: Awaited<ReturnType<PublicClient['getLogs']>> = []

    // Crear array de rangos
    const ranges: Array<{ from: bigint; to: bigint }> = []
    let cursor = fromBlock
    while (cursor <= toBlock) {
        const end = cursor + chunkSize - 1n < toBlock ? cursor + chunkSize - 1n : toBlock
        ranges.push({ from: cursor, to: end })
        cursor = end + 1n
    }

    // Ejecutar en batches de 5 para no saturar el RPC
    const BATCH_SIZE = 5
    for (let i = 0; i < ranges.length; i += BATCH_SIZE) {
        const batch = ranges.slice(i, i + BATCH_SIZE)
        const results = await Promise.all(
            batch.map(({ from, to }) =>
                client.getLogs({
                    ...rest,
                    fromBlock: from,
                    toBlock: to,
                } as GetLogsParameters),
            ),
        )
        for (const r of results) allLogs.push(...(r as any))
    }

    return allLogs
}
