import app from "ags/gtk4/app"
import { Astal, Gdk, Gtk } from "ags/gtk4"
import GLib from "gi://GLib?version=2.0"
import { startPollers } from "./lib/store"
import { Clock, CpuCard, MediaCard, NetworkCard, RingsCard, StorageCard, WeatherCard } from "./widget/Cards"

declare const SRC: string
const root = typeof SRC !== "undefined" ? SRC : GLib.get_current_dir()

function Mimosa(gdkmonitor: Gdk.Monitor) {
    const { TOP, LEFT } = Astal.WindowAnchor
    return (
        <window
            visible
            namespace="mimosa-ags"
            class="mimosa"
            gdkmonitor={gdkmonitor}
            application={app}
            anchor={TOP | LEFT}
            layer={Astal.Layer.BACKGROUND}
            exclusivity={Astal.Exclusivity.IGNORE}
            keymode={Astal.Keymode.NONE}
            marginTop={50}
            marginLeft={30}
        >
            <box orientation={Gtk.Orientation.VERTICAL} class="column" spacing={10} widthRequest={300}>
                <Clock />
                <box spacing={10} homogeneous>
                    <WeatherCard />
                    <NetworkCard />
                </box>
                <RingsCard />
                <CpuCard />
                <StorageCard />
                <MediaCard />
            </box>
        </window>
    )
}

app.start({
    instanceName: "mimosa",
    requestHandler(request, res) {
        res("ok")
    },
    css: `${root}/style.css`,
    main() {
        startPollers()
        // Show on the primary monitor only (first in the list).
        const mon = app.get_monitors()[0]
        if (mon) Mimosa(mon)
    },
})

