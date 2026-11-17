// Central reactive store: one 1 Hz collector feeding a single state object,
// plus slower pollers (weather, disks, SSID, media).
import { createState } from "ags"
import { exec, execAsync } from "ags/process"
import GLib from "gi://GLib?version=2.0"
import {
    CpuTimes, parseCpuList, readBattery, readCpuTimes, readGpuLoad, readMem, readNet,
    readTempC, readVram, usage, cpuFreqGHz, readText, fileExists,
} from "./sys"

declare const SRC: string
export const ROOT: string = typeof SRC !== "undefined" ? SRC : GLib.get_current_dir()
export const SCRIPTS = `${ROOT}/scripts`

export type Hw = {
    cpu_name: string
    core_siblings: string[]
    physical_cores: number
    logical_threads: number
    is_hybrid: boolean
    has_battery: boolean
    battery_dev: string
    active_iface: string
    gpu_type: string
    drm_card_path: string
    vram_total: number
    cpu_temp_path: string
}

const FALLBACK_HW: Hw = {
    cpu_name: "PROCESSOR", core_siblings: [], physical_cores: 4, logical_threads: 4,
    is_hybrid: false, has_battery: false, battery_dev: "", active_iface: "lo",
    gpu_type: "igpu", drm_card_path: "", vram_total: 0, cpu_temp_path: "",
}

function loadHw(): Hw {
    try {
        return { ...FALLBACK_HW, ...JSON.parse(exec(["bash", `${SCRIPTS}/hw-detect.sh`])) }
    } catch (e) {
        console.error("hw-detect failed:", e)
        return FALLBACK_HW
    }
}

export const hw: Hw = loadHw()

/** Logical CPU ids per physical core, ordered by first thread id. */
export const coreGroups: number[][] = (hw.core_siblings.length
    ? hw.core_siblings.map(parseCpuList).filter((g) => g.length)
    : Array.from({ length: hw.logical_threads }, (_, i) => [i])
).sort((a, b) => a[0] - b[0])

export type Stats = {
    cpuTotal: number
    cores: number[]
    freq: number
    temp: number
    ramUsed: number
    ramTotal: number
    swapUsed: number
    swapTotal: number
    vramUsed: number
    vramTotal: number
    battery: number
    gpu: number
    rxRate: number
    txRate: number
    rxTotal: number
    txTotal: number
    rxHist: number[]
    txHist: number[]
    clock: string
    date: string
}

const HIST = 30
const zeros = () => Array.from({ length: HIST }, () => 0)

const [stats, setStats] = createState<Stats>({
    cpuTotal: 0, cores: coreGroups.map(() => 0), freq: 0, temp: 0,
    ramUsed: 0, ramTotal: 1, swapUsed: 0, swapTotal: 0, vramUsed: 0, vramTotal: 0,
    battery: 0, gpu: 0, rxRate: 0, txRate: 0, rxTotal: 0, txTotal: 0,
    rxHist: zeros(), txHist: zeros(), clock: "", date: "",
})
export { stats }

let prevCpu: CpuTimes[] = readCpuTimes()
let prevNet = readNet(hw.active_iface)

function tick(): boolean {
    const cur = readCpuTimes()
    const net = readNet(hw.active_iface)
    const mem = readMem()
    const vram = readVram(hw.drm_card_path)
    const now = GLib.DateTime.new_now_local()
    const prev = stats.peek()

    const cores = coreGroups.map((ids) => {
        const v = ids.map((i) => usage(prevCpu[i], cur[i]))
        return v.reduce((a, b) => a + b, 0) / (v.length || 1)
    })
    const rx = Math.max(0, net.rx - prevNet.rx)
    const tx = Math.max(0, net.tx - prevNet.tx)

    setStats({
        cpuTotal: cores.reduce((a, b) => a + b, 0) / (cores.length || 1),
        cores,
        freq: cpuFreqGHz(),
        temp: readTempC(hw.cpu_temp_path),
        ramUsed: mem.used, ramTotal: mem.total,
        swapUsed: mem.swapUsed, swapTotal: mem.swapTotal,
        vramUsed: vram.used, vramTotal: vram.total,
        battery: hw.has_battery ? readBattery(hw.battery_dev) : 0,
        gpu: readGpuLoad(hw.drm_card_path),
        rxRate: rx, txRate: tx, rxTotal: net.rx, txTotal: net.tx,
        rxHist: [...prev.rxHist.slice(1), rx],
        txHist: [...prev.txHist.slice(1), tx],
        clock: now.format("%H:%M")!,
        date: now.format("%A %d %B")!,
    })
    prevCpu = cur
    prevNet = net
    return GLib.SOURCE_CONTINUE
}

// ---------- slower pollers ----------
export type Weather = { icon: string; temp: string; city: string; desc: string; wind: string; humidity: string }
const [weather, setWeather] = createState<Weather>({
    icon: "", temp: "--", city: "", desc: "", wind: "-", humidity: "-",
})
export { weather }

async function refreshWeather() {
    try {
        const w = `${SCRIPTS}/weather-v4.0.sh`
        await execAsync(["bash", w, "-g"])
        const one = async (f: string) => (await execAsync(["bash", w, f])).trim()
        const [icon, temp, city, desc, wind, humidity] = await Promise.all(
            ["-i", "-t", "-n", "-d", "-ws", "-h"].map(one),
        )
        setWeather({ icon, temp, city, desc, wind, humidity })
    } catch (e) {
        console.error("weather:", e)
    }
}

const [ssid, setSsid] = createState("")
export { ssid }
async function refreshSsid() {
    try {
        setSsid((await execAsync(["bash", `${SCRIPTS}/ssid`])).trim())
    } catch {
        setSsid("")
    }
}

export type Disk = { target: string; label: string; size: number; used: number }
const [disks, setDisks] = createState<Disk[]>([])
export { disks }

const FS_OK = /^(ext[234]|btrfs|xfs|f2fs|ntfs3?|fuseblk|exfat|vfat)$/
async function refreshDisks() {
    try {
        const out = await execAsync(["df", "-PT", "-B1"])
        const rows: Disk[] = []
        const seen = new Set<string>()
        for (const line of out.split("\n").slice(1)) {
            const p = line.trim().split(/\s+/)
            if (p.length < 7 || !FS_OK.test(p[1])) continue
            const target = p.slice(6).join(" ")
            if (target.startsWith("/boot") || target.startsWith("/var/lib") || seen.has(p[0])) continue
            seen.add(p[0])
            const base = target === "/" ? "System" : target.split("/").pop() || target
            rows.push({ target, label: base, size: Number(p[2]), used: Number(p[3]) })
        }
        rows.sort((a, b) => (a.target === "/" ? -1 : b.target === "/" ? 1 : a.target.localeCompare(b.target)))
        setDisks(rows.slice(0, 4))
    } catch (e) {
        console.error("disks:", e)
    }
}

export type Media = {
    status: string
    artist: string
    title: string
    time: string
    cover: string
    percent: number
}
const [media, setMedia] = createState<Media>({
    status: "Stopped",
    artist: "Media Player",
    title: "No music playing",
    time: "Idle",
    cover: "",
    percent: 0,
})
export { media }

function parseMediaState(raw: string): Record<string, string> {
    const out: Record<string, string> = {}
    for (const line of raw.split("\n")) {
        const m = line.match(/^PCTL_([A-Z]+)=(.*)$/)
        if (m) {
            let val = m[2].trim()
            if ((val.startsWith("'") && val.endsWith("'")) || (val.startsWith('"') && val.endsWith('"'))) {
                val = val.slice(1, -1)
            }
            val = val.replace(/\\(.)/g, "$1")
            out[m[1]] = val
        }
    }
    return out
}

function refreshMedia() {
    try {
        const text = readText("/tmp/conky_media_state")
        if (!text) {
            setMedia({
                status: "Stopped",
                artist: "Media Player",
                title: "No music playing",
                time: "Idle",
                cover: "",
                percent: 0,
            })
            return
        }
        const st = parseMediaState(text)
        const status = st.STATUS || "Stopped"
        const artist = st.ARTIST || "Media Player"
        const title = st.TITLE || "No music playing"
        const time = st.TIME || "Idle"
        const percent = Math.max(0, Math.min(100, Number(st.PERC) || 0))
        const cover = fileExists("/tmp/conky_cover.png") ? "/tmp/conky_cover.png" : ""

        setMedia({
            status,
            artist,
            title,
            time,
            cover,
            percent,
        })
    } catch (e) {
        console.error("refreshMedia error:", e)
    }
}

export function startPollers() {
    tick()
    refreshMedia()
    GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
        tick()
        refreshMedia()
        return GLib.SOURCE_CONTINUE
    })
    const every = (sec: number, fn: () => Promise<void>) => {
        fn()
        GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, sec, () => {
            fn()
            return GLib.SOURCE_CONTINUE
        })
    }
    every(600, refreshWeather)
    every(5, refreshSsid)
    every(15, refreshDisks)
}

