import { Accessor } from "ags"
import { Gtk } from "ags/gtk4"

type RGBA = [number, number, number, number]
const GREEN: RGBA = [0.196, 0.843, 0.298, 1]   // #32d74c
const AMBER: RGBA = [1.0, 0.624, 0.039, 1]     // #ff9f0a
const RED: RGBA   = [1.0, 0.271, 0.227, 1]     // #ff453a
const TRACK: RGBA = [1, 1, 1, 0.12]

function getRingColor(pctVal: number, invert?: boolean): RGBA {
    if (invert) {
        if (pctVal <= 20) return RED
        if (pctVal <= 40) return AMBER
        return GREEN
    }
    if (pctVal >= 80) return RED
    if (pctVal >= 60) return AMBER
    return GREEN
}

/** Circular progress ring drawn with Cairo; text is real GTK labels (no manual text math). */
export function Ring(props: {
    value: Accessor<number> // 0..100
    icon: string | Accessor<string>
    title: string
    text?: Accessor<string>
    size?: number
    invertColor?: boolean
    centerClass?: string | Accessor<string>
}) {
    const size = props.size ?? 58
    const stroke = 6

    return (
        <box orientation={Gtk.Orientation.VERTICAL} class="ring" halign={Gtk.Align.CENTER} spacing={2}>
            <overlay>
                <drawingarea
                    $={(area: Gtk.DrawingArea) => {
                        area.set_content_width(size)
                        area.set_content_height(size)
                        area.set_draw_func((_a, cr, w, h) => {
                            const cx = w / 2
                            const cy = h / 2
                            const r = (Math.min(w, h) - stroke) / 2
                            const pctVal = Math.max(0, Math.min(100, props.value.peek()))
                            const v = pctVal / 100
                            cr.setLineWidth(stroke)
                            cr.setLineCap(1) // ROUND
                            cr.setSourceRGBA(...TRACK)
                            cr.arc(cx, cy, r, 0, Math.PI * 2)
                            cr.stroke()
                            if (v > 0) {
                                cr.setSourceRGBA(...getRingColor(pctVal, props.invertColor))
                                cr.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * v)
                                cr.stroke()
                            }
                        })
                        props.value.subscribe(() => area.queue_draw())
                    }}
                />
                <label
                    $type="overlay"
                    class={props.centerClass ?? "ring-icon"}
                    label={props.icon}
                    halign={Gtk.Align.CENTER}
                    valign={Gtk.Align.CENTER}
                />
            </overlay>
            <label class="ring-title" label={props.title} />
            {props.text ? <label class="ring-value" label={props.text} /> : <box />}
        </box>
    )
}

