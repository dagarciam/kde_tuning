const UNITS = ["B", "KiB", "MiB", "GiB", "TiB"]

/** 15.6 GiB style, used for totals and disk sizes. */
export function fmtBytes(n: number, digits = 1): string {
    let i = 0
    while (n >= 1024 && i < UNITS.length - 1) {
        n /= 1024
        i++
    }
    return i === 0 ? `${Math.round(n)}B` : `${n.toFixed(n >= 100 ? 0 : digits)}${UNITS[i]}`
}

/** Compact memory string for ring values: 2.9G / 512M. */
export function fmtShort(n: number): string {
    if (n >= 1024 ** 3) return `${(n / 1024 ** 3).toFixed(1)}G`
    if (n >= 1024 ** 2) return `${Math.round(n / 1024 ** 2)}M`
    return `${Math.round(n / 1024)}K`
}

export const pct = (n: number) => `${Math.round(n)}%`

export const pad2 = (n: number) => String(n).padStart(2, "0")

