import { For } from "ags"
import { Gtk } from "ags/gtk4"
import { fmtBytes, fmtShort, pad2, pct } from "../lib/format"
import { coreGroups, disks, hw, media, ssid, stats, weather } from "../lib/store"
import { Ring } from "./Ring"
import { Sparkline } from "./Sparkline"

const V = Gtk.Orientation.VERTICAL
const H = Gtk.Orientation.HORIZONTAL
const START = Gtk.Align.START
const END = Gtk.Align.END

export function Clock() {
    return (
        <box orientation={V} class="clock" halign={START}>
            <label class="clock-time" halign={START} label={stats.as((s) => s.clock)} />
            <label class="clock-date" halign={START} label={stats.as((s) => s.date)} />
        </box>
    )
}

export function WeatherCard() {
    return (
        <box orientation={V} class="card weather" hexpand>
            <box spacing={10}>
                <label class="weather-icon" label={weather.as((w) => w.icon)} />
                <label class="weather-temp" label={weather.as((w) => `${w.temp}°C`)} />
            </box>
            <label class="weather-city" halign={START} label={weather.as((w) => w.city)} />
            <label class="weather-desc" halign={START} label={weather.as((w) => w.desc)} />
            <label class="small" halign={START} label={weather.as((w) => `Wind speed : ${w.wind}m/s`)} />
            <label class="small" halign={START} label={weather.as((w) => `Humidity : ${w.humidity}%`)} />
        </box>
    )
}

export function NetworkCard() {
    return (
        <box orientation={V} class="card network" hexpand spacing={2}>
            <label class="net-ssid" halign={START} label={ssid} />
            <box>
                <label class="small" label={stats.as((s) => `Dn : ${fmtBytes(s.rxRate)}`)} />
                <label class="small" hexpand halign={END} label={stats.as((s) => `>>  ${fmtBytes(s.rxTotal)}`)} />
            </box>
            <Sparkline data={stats.as((s) => s.rxHist)} color={[1, 0.55, 0.35]} />
            <box>
                <label class="small" label={stats.as((s) => `Up : ${fmtBytes(s.txRate)}`)} />
                <label class="small" hexpand halign={END} label={stats.as((s) => `>>  ${fmtBytes(s.txTotal)}`)} />
            </box>
            <Sparkline data={stats.as((s) => s.txHist)} color={[0.2, 0.84, 0.3]} />
        </box>
    )
}

export function RingsCard() {
    // 2nd ring: battery on laptops, VRAM (or swap) on desktops
    const second = hw.has_battery
        ? { icon: "󰁹", title: "BAT", value: stats.as((s) => s.battery), text: stats.as((s) => pct(s.battery)) }
        : hw.vram_total > 0
          ? {
                icon: "󰍹", title: "VRAM",
                value: stats.as((s) => (s.vramTotal ? (s.vramUsed / s.vramTotal) * 100 : 0)),
                text: stats.as((s) => fmtShort(s.vramUsed)),
            }
          : {
                icon: "󰾴", title: "SWAP",
                value: stats.as((s) => (s.swapTotal ? (s.swapUsed / s.swapTotal) * 100 : 0)),
                text: stats.as((s) => fmtShort(s.swapUsed)),
            }

    return (
        <box class="card rings" homogeneous>
            <Ring
                icon="󰍛" title="RAM"
                value={stats.as((s) => (s.ramUsed / s.ramTotal) * 100)}
                text={stats.as((s) => fmtShort(s.ramUsed))}
            />
            <Ring {...second} />
            <Ring icon="󰢮" title="GPU" value={stats.as((s) => s.gpu)} text={stats.as((s) => pct(s.gpu))} />
            <Ring icon="󰔏" title="TEMP" value={stats.as((s) => s.temp)} text={stats.as((s) => `${Math.round(s.temp)}°C`)} />
        </box>
    )
}

function CoreRow(props: { n: number }) {
    return (
        <box class="core-row" spacing={6}>
            <label class="core-label" label={`C${pad2(props.n + 1)}`} />
            <progressbar class="core-bar" hexpand valign={Gtk.Align.CENTER} fraction={stats.as((s) => (s.cores[props.n] ?? 0) / 100)} />
            <label class="core-pct" label={stats.as((s) => pct(s.cores[props.n] ?? 0))} />
        </box>
    )
}

export function CpuCard() {
    const n = coreGroups.length
    // Hybrid CPUs: P-cores are the SMT ones (2 threads), E-cores single thread.
    const half = Math.ceil(n / 2)
    const cols = [Array.from({ length: half }, (_, i) => i), Array.from({ length: n - half }, (_, i) => half + i)]
    const titles = hw.is_hybrid
        ? ["PERF · CORES", "EFF · CORES"]
        : cols.map((c) => (c.length ? `CORES ${pad2(c[0] + 1)}-${pad2(c[c.length - 1] + 1)}` : ""))

    return (
        <box orientation={V} class="card cpu" spacing={8}>
            <box>
                <label class="cpu-icon" label="" />
                <label class="cpu-name" label={hw.cpu_name} />
                <box hexpand />
                <label class="cpu-temp" label={stats.as((s) => `${Math.round(s.temp)}°C`)} />
                <label class="cpu-freq" label={stats.as((s) => `${s.freq.toFixed(2)}GHz`)} />
            </box>
            <box spacing={14}>
                <box orientation={V} valign={Gtk.Align.CENTER}>
                    <Ring icon="" title="CPU TOTAL" value={stats.as((s) => s.cpuTotal)} text={stats.as((s) => pct(s.cpuTotal))} size={52} />
                    <label class="small dim" label={`${n} CORES · ${hw.logical_threads} TH`} />
                </box>
                {cols.map((c, i) => (
                    <box orientation={V} hexpand spacing={3}>
                        <label class="core-title" halign={START} label={titles[i]} />
                        {c.map((idx) => (
                            <CoreRow n={idx} />
                        ))}
                    </box>
                ))}
            </box>
        </box>
    )
}

export function StorageCard() {
    return (
        <box orientation={V} class="card storage" spacing={6}>
            <label class="card-title" halign={START} label="Storage" />
            <For each={disks}>
                {(d) => (
                    <box orientation={V} class="disk" spacing={2}>
                        <box>
                            <label class="small" label={`${d.label}: ${Math.round((d.used / d.size) * 100)}% (${fmtBytes(d.used)} / ${fmtBytes(d.size)})`} />
                            <label class="small free" hexpand halign={END} label={`Free: ${fmtBytes(d.size - d.used, 0)}`} />
                        </box>
                        <progressbar class="disk-bar" fraction={d.size ? d.used / d.size : 0} />
                    </box>
                )}
            </For>
        </box>
    )
}

export function MediaCard() {
    return (
        <box class="card media" spacing={14}>
            <box class="cover" valign={Gtk.Align.CENTER}>
                <Gtk.Picture
                    class="cover-img"
                    contentFit={Gtk.ContentFit.COVER}
                    widthRequest={64}
                    heightRequest={64}
                    $={(pic: Gtk.Picture) => {
                        media.subscribe(() => {
                            const c = media.peek().cover
                            pic.set_filename(c || null)
                        })
                    }}
                />
            </box>
            <box orientation={V} valign={Gtk.Align.CENTER} hexpand>
                <label class="media-label" halign={START} label="Media Player" />
                <label
                    class="media-title" halign={START} hexpand wrap={false}
                    ellipsize={3} maxWidthChars={22}
                    label={media.as((m) => m.title || "No music playing")}
                />
                <label
                    class="small dim" halign={START}
                    label={media.as((m) => (m.artist ? `${m.artist} · ${m.status}` : m.status || "Idle"))}
                />
            </box>
        </box>
    )
}
