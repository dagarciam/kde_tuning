import { For } from "ags"
import { Gtk } from "ags/gtk4"
import Gdk from "gi://Gdk?version=4.0"
import GdkPixbuf from "gi://GdkPixbuf?version=2.0"
import Gio from "gi://Gio?version=2.0"
import GLib from "gi://GLib?version=2.0"
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
        ? { icon: "󰁹", title: "BAT", invertColor: true, value: stats.as((s) => s.battery), text: stats.as((s) => pct(s.battery)) }
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
            <levelbar
                class={stats.as((s) => {
                    const v = s.cores[props.n] ?? 0
                    return v >= 80 ? "core-bar crit" : v >= 60 ? "core-bar warn" : "core-bar"
                })}
                hexpand
                valign={Gtk.Align.CENTER}
                minValue={0}
                maxValue={1}
                value={stats.as((s) => (s.cores[props.n] ?? 0) / 100)}
            />
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
                        <levelbar
                            class="disk-bar"
                            minValue={0}
                            maxValue={1}
                            value={d.size ? d.used / d.size : 0}
                        />
                    </box>
                )}
            </For>
        </box>
    )
}

export function MediaCard() {
    let angle = 0
    let pb: GdkPixbuf.Pixbuf | null = null
    let lastTrackKey = ""

    function loadCover(c: string) {
        if (!c) {
            pb = null
            return
        }
        try {
            pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(c, 58, 58, false)
        } catch {
            pb = null
        }
    }

    return (
        <box orientation={V} class="card media" spacing={8}>
            <box spacing={12} valign={Gtk.Align.CENTER}>
                <box class="cover" valign={Gtk.Align.CENTER}>
                    <drawingarea
                        $={(area: Gtk.DrawingArea) => {
                            area.set_content_width(58)
                            area.set_content_height(58)
                            loadCover(media.peek().cover)
                            media.subscribe(() => {
                                const m = media.peek()
                                const trackKey = `${m.artist}|${m.title}|${m.cover}`
                                if (trackKey !== lastTrackKey) {
                                    lastTrackKey = trackKey
                                    loadCover(m.cover)
                                    area.queue_draw()
                                }
                            })
                            area.set_draw_func((_a, cr, w, h) => {
                                const cx = w / 2
                                const cy = h / 2
                                cr.save()
                                cr.translate(cx, cy)
                                cr.rotate(angle)
                                cr.arc(0, 0, Math.min(w, h) / 2, 0, Math.PI * 2)
                                cr.clip()
                                if (pb) {
                                    Gdk.cairo_set_source_pixbuf(cr, pb, -pb.get_width() / 2, -pb.get_height() / 2)
                                    cr.paint()
                                } else {
                                    cr.setSourceRGBA(0.1, 0.1, 0.1, 1)
                                    cr.paint()
                                }
                                cr.restore()
                            })
                            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
                                const st = media.peek().status
                                if (st === "Playing") {
                                    angle = (angle + 0.1745329) % (2 * Math.PI)
                                    area.queue_draw()
                                } else if (st === "Stopped" || !st) {
                                    if (angle !== 0) {
                                        angle = 0
                                        area.queue_draw()
                                    }
                                }
                                return GLib.SOURCE_CONTINUE
                            })
                        }}
                    />
                </box>
                <box orientation={V} valign={Gtk.Align.CENTER} hexpand spacing={2}>
                    <label
                        class="media-artist"
                        halign={START}
                        wrap={false}
                        ellipsize={3}
                        maxWidthChars={20}
                        label={media.as((m) => m.artist)}
                    />
                    <label
                        class="media-title"
                        halign={START}
                        wrap={false}
                        ellipsize={3}
                        maxWidthChars={20}
                        label={media.as((m) => m.title)}
                    />
                    <label
                        class="small dim"
                        halign={START}
                        label={media.as((m) => (m.time && m.time !== "Idle" ? `⊙ ${m.time}` : "⊙ Idle"))}
                    />
                </box>
            </box>
            <drawingarea
                hexpand
                $={(area: Gtk.DrawingArea) => {
                    let wavePhase = 0
                    area.set_content_height(14)
                    media.subscribe(() => area.queue_draw())
                    area.set_draw_func((_a, cr, w, h) => {
                        const m = media.peek()
                        const pad = 4
                        const x1 = pad
                        const x2 = Math.max(pad + 1, w - pad)
                        const baseY = h / 2
                        const perc = Math.max(0, Math.min(100, m.percent || 0))
                        const currX = x1 + (perc / 100) * (x2 - x1)

                        if (!m.status || m.status === "Stopped") {
                            cr.setLineWidth(2.5)
                            cr.setLineCap(1) // ROUND
                            cr.setSourceRGBA(1, 1, 1, 0.12)
                            cr.moveTo(x1, baseY)
                            cr.lineTo(x2, baseY)
                            cr.stroke()
                            return
                        }

                        // 1. Unplayed portion
                        if (currX < x2) {
                            cr.setLineWidth(2.5)
                            cr.setLineCap(1)
                            cr.setSourceRGBA(1, 1, 1, 0.18)
                            cr.moveTo(currX, baseY)
                            cr.lineTo(x2, baseY)
                            cr.stroke()
                        }

                        // 2. Played portion (squiggly wave when playing, flat when paused)
                        if (currX > x1) {
                            cr.setLineWidth(2.8)
                            cr.setLineCap(1)
                            cr.setLineJoin(1) // ROUND
                            cr.setSourceRGBA(0.196, 0.8431, 0.298, 1) // #32d74c
                            if (m.status === "Playing" && currX - x1 > 8) {
                                const wavelength = 16
                                const amplitude = 2.4
                                cr.moveTo(x1, baseY)
                                for (let x = x1 + 1; x <= currX; x += 1) {
                                    const taperStart = Math.min(1, (x - x1) / 8)
                                    const taperEnd = Math.min(1, (currX - x) / 8)
                                    const env = taperStart * taperEnd
                                    const wy = baseY + env * amplitude * Math.sin(((x - x1) * 2 * Math.PI) / wavelength - wavePhase)
                                    cr.lineTo(x, wy)
                                }
                                cr.stroke()
                            } else {
                                cr.moveTo(x1, baseY)
                                cr.lineTo(currX, baseY)
                                cr.stroke()
                            }
                        }

                        // 3. Thumb indicator
                        cr.arc(currX, baseY, 3.8, 0, Math.PI * 2)
                        cr.setSourceRGBA(1, 1, 1, 1)
                        cr.fill()
                    })
                    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
                        if (media.peek().status === "Playing") {
                            wavePhase = (wavePhase + 0.10) % (2 * Math.PI)
                            area.queue_draw()
                        }
                        return GLib.SOURCE_CONTINUE
                    })
                }}
            />
        </box>
    )
}

