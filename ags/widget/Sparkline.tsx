import { Accessor } from "ags"
import { Gtk } from "ags/gtk4"

/** Tiny filled sparkline (network history). */
export function Sparkline(props: { data: Accessor<number[]>; color: [number, number, number]; height?: number }) {
    return (
        <drawingarea
            class="spark"
            hexpand
            $={(area: Gtk.DrawingArea) => {
                area.set_content_height(props.height ?? 24)
                area.set_draw_func((_a, cr, w, h) => {
                    const d = props.data.peek()
                    const max = Math.max(1024, ...d)
                    const step = w / (d.length - 1)
                    cr.setSourceRGBA(props.color[0], props.color[1], props.color[2], 0.85)
                    cr.moveTo(0, h)
                    d.forEach((v, i) => cr.lineTo(i * step, h - (v / max) * (h - 2)))
                    cr.lineTo(w, h)
                    cr.closePath()
                    cr.fill()
                })
                props.data.subscribe(() => area.queue_draw())
            }}
        />
    )
}
