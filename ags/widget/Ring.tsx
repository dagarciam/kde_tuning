import { Accessor } from "ags"
import { Gtk } from "ags/gtk4"

type RGBA = [number, number, number, number]
const GREEN: RGBA = [0.196, 0.843, 0.298, 1]
const TRACK: RGBA = [1, 1, 1, 0.12]

/** Circular progress ring drawn with Cairo; text is real GTK labels (no manual text math). */
export function Ring(props: {
    value: Accessor<number> // 0..100
    icon: string
    title: string
    text: Accessor<string>
    size?: number
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
                            const v = Math.max(0, Math.min(100, props.value.peek())) / 100
                            cr.setLineWidth(stroke)
                            cr.setLineCap(1) // ROUND
                            cr.setSourceRGBA(...TRACK)
                            cr.arc(cx, cy, r, 0, Math.PI * 2)
                            cr.stroke()
                            if (v > 0) {
                                cr.setSourceRGBA(...GREEN)
                                cr.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * v)
                                cr.stroke()
                            }
                        })
                        props.value.subscribe(() => area.queue_draw())
                    }}
                />
                <label
                    $type="overlay"
                    class="ring-icon"
                    label={props.icon}
                    halign={Gtk.Align.CENTER}
                    valign={Gtk.Align.CENTER}
                />
            </overlay>
            <label class="ring-title" label={props.title} />
            <label class="ring-value" label={props.text} />
        </box>
    )
}

