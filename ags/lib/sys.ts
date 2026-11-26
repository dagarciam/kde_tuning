// Low-level system readers (procfs / sysfs). Kept dependency-light and defensive:
// every reader returns a safe default instead of throwing.
import GLib from "gi://GLib?version=2.0"

const decoder = new TextDecoder()

export function readText(path: string): string {
    try {
        const [ok, bytes] = GLib.file_get_contents(path)
        return ok ? decoder.decode(bytes).trim() : ""
    } catch {
        return ""
    }
}

export function readNum(path: string, fallback = 0): number {
    const n = Number(readText(path))
    return Number.isFinite(n) ? n : fallback
}

export function fileExists(path: string): boolean {
    return GLib.file_test(path, GLib.FileTest.EXISTS)
}

// ---------- CPU ----------
export type CpuTimes = { idle: number; total: number }

/** Parses /proc/stat into per-logical-cpu counters (index = cpu id). */
export function readCpuTimes(): CpuTimes[] {
    const out: CpuTimes[] = []
    for (const line of readText("/proc/stat").split("\n")) {
        const m = line.match(/^cpu(\d+)\s+(.*)$/)
        if (!m) continue
        const v = m[2].split(/\s+/).map(Number)
        const idle = (v[3] ?? 0) + (v[4] ?? 0) // idle + iowait
        const total = v.slice(0, 8).reduce((a, b) => a + b, 0)
        out[Number(m[1])] = { idle, total }
    }
    return out
}

export function usage(prev: CpuTimes | undefined, cur: CpuTimes | undefined): number {
    if (!prev || !cur) return 0
    const dt = cur.total - prev.total
    const di = cur.idle - prev.idle
    return dt > 0 ? Math.max(0, Math.min(100, (1 - di / dt) * 100)) : 0
}

/** "0-1" | "0,1" | "4" -> [0,1] | [0,1] | [4] */
export function parseCpuList(s: string): number[] {
    const ids: number[] = []
    for (const part of s.split(",")) {
        const r = part.match(/^(\d+)-(\d+)$/)
        if (r) for (let i = Number(r[1]); i <= Number(r[2]); i++) ids.push(i)
        else if (/^\d+$/.test(part)) ids.push(Number(part))
    }
    return ids
}

export function cpuFreqGHz(): number {
    let sum = 0
    let n = 0
    for (let i = 0; i < 256; i++) {
        const p = `/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_cur_freq`
        if (!fileExists(p)) break
        sum += readNum(p)
        n++
    }
    return n ? sum / n / 1e6 : 0
}

// ---------- Memory ----------
export type Mem = { total: number; used: number; swapTotal: number; swapUsed: number }

export function readMem(): Mem {
    const kv: Record<string, number> = {}
    for (const line of readText("/proc/meminfo").split("\n")) {
        const m = line.match(/^(\w+):\s+(\d+)/)
        if (m) kv[m[1]] = Number(m[2]) * 1024
    }
    const total = kv.MemTotal ?? 0
    return {
        total,
        used: total - (kv.MemAvailable ?? 0),
        swapTotal: kv.SwapTotal ?? 0,
        swapUsed: (kv.SwapTotal ?? 0) - (kv.SwapFree ?? 0),
    }
}

// ---------- Network ----------
export function readNet(iface: string): { rx: number; tx: number } {
    for (const line of readText("/proc/net/dev").split("\n")) {
        const t = line.trim()
        if (!t.startsWith(iface + ":")) continue
        const v = t.slice(iface.length + 1).trim().split(/\s+/).map(Number)
        return { rx: v[0] ?? 0, tx: v[8] ?? 0 }
    }
    return { rx: 0, tx: 0 }
}

// ---------- Battery / thermal / GPU ----------
export function readBattery(dev: string): number {
    return dev ? readNum(`/sys/class/power_supply/${dev}/capacity`) : 0
}

export function readBatteryStatus(dev: string): string {
    return dev ? readText(`/sys/class/power_supply/${dev}/status`) : ""
}

export function readTempC(path: string): number {
    return path ? readNum(path) / 1000 : 0
}

/** Best-effort GPU utilisation 0..100 for amdgpu / intel (freq ratio). */
export function readGpuLoad(drmDevPath: string): number {
    if (!drmDevPath) return 0
    const busy = `${drmDevPath}/gpu_busy_percent`
    if (fileExists(busy)) return readNum(busy)
    const card = drmDevPath.replace(/\/device$/, "")
    const act = `${card}/gt/gt0/rps_act_freq_mhz`
    const max = `${card}/gt/gt0/rps_max_freq_mhz`
    if (fileExists(act) && fileExists(max)) {
        const m = readNum(max)
        return m > 0 ? Math.min(100, (readNum(act) / m) * 100) : 0
    }
    return 0
}

export function readVram(drmDevPath: string): { total: number; used: number } {
    if (!drmDevPath) return { total: 0, used: 0 }
    return {
        total: readNum(`${drmDevPath}/mem_info_vram_total`),
        used: readNum(`${drmDevPath}/mem_info_vram_used`),
    }
}

// ---------- OS & Kernel & Uptime ----------
export function readKernel(): string {
    const raw = readText("/proc/sys/kernel/osrelease")
    return raw || "Linux"
}

export function readUptime(): string {
    const raw = readText("/proc/uptime")
    if (!raw) return ""
    const secs = Math.floor(Number(raw.split(/\s+/)[0]) || 0)
    const days = Math.floor(secs / 86400)
    const hours = Math.floor((secs % 86400) / 3600)
    const mins = Math.floor((secs % 3600) / 60)
    if (days > 0) return `${days}d ${hours}h`
    if (hours > 0) return `${hours}h ${mins}m`
    return `${mins}m`
}

export type OsRelease = {
    name: string
    id: string
    icon: string
}

export function readOsRelease(): OsRelease {
    const text = readText("/etc/os-release")
    let name = ""
    let id = "linux"
    let idLike = ""
    for (const line of text.split("\n")) {
        const m = line.match(/^([A-Z_]+)=(.*)$/)
        if (!m) continue
        const key = m[1]
        let val = m[2].trim()
        if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
            val = val.slice(1, -1)
        }
        if (key === "PRETTY_NAME" && !name) name = val
        if (key === "NAME" && (!name || name === "Linux")) name = val
        if (key === "ID") id = val.toLowerCase()
        if (key === "ID_LIKE") idLike = val.toLowerCase()
    }
    if (!name) name = "Linux"

    const s = id.toLowerCase()
    let icon = ""
    if (s.includes("manjaro")) icon = ""
    else if (s.includes("endeavouros")) icon = ""
    else if (s.includes("garuda")) icon = ""
    else if (s.includes("cachyos") || s.includes("arch")) icon = ""
    else if (s.includes("fedora")) icon = ""
    else if (s.includes("ubuntu") || s.includes("neon") || s.includes("tuxedo")) icon = ""
    else if (s.includes("debian")) icon = ""
    else if (s.includes("opensuse") || s.includes("suse")) icon = ""
    else if (s.includes("nixos")) icon = ""
    else if (s.includes("gentoo")) icon = ""
    else if (s.includes("void")) icon = ""
    else if (s.includes("alpine")) icon = ""
    else if (s.includes("pop")) icon = ""
    else if (s.includes("mint")) icon = "󰣭"
    else if (idLike.includes("arch")) icon = ""
    else if (idLike.includes("fedora") || idLike.includes("rhel")) icon = ""
    else if (idLike.includes("ubuntu")) icon = ""
    else if (idLike.includes("debian")) icon = ""
    else if (idLike.includes("suse")) icon = ""

    return { name, id, icon }
}


