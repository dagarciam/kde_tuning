--[==[
	Version		: 2.2
	Author		: Closebox73 (Adaptive Storage Bars for Desktop & Laptop)
	Description	: Draws storage bars dynamically:
	              - 1 partition (typical laptop): Single centered hero bar with used & available stats
	              - 2 partitions: Stacked full-width bars
	              - 3 or 4 partitions (desktop): 2x2 grid
]==]

require 'cairo'
require 'cairo_xlib'

local PALETTE = {
    {1.0, 0.2705, 0.2235, 1.0}, -- Coral red
    {0.1960, 0.8431, 0.2980, 1.0}, -- Bright green
    {0.0, 0.7843, 1.0, 1.0},    -- Cyan
    {1.0, 0.6235, 0.0392, 1.0}, -- Amber orange
}

local VALID_FS = {
    ext4 = true, ext3 = true, ext2 = true,
    btrfs = true, xfs = true, f2fs = true, zfs = true,
    ntfs = true, ntfs3 = true, fuseblk = true,
    vfat = true, exfat = true,
}

-- Parse /proc/mounts to get active real storage mountpoints
local function get_active_mounts()
    local mounted = {}
    local ordered_extra = {}
    local f = io.open("/proc/mounts", "r")
    if not f then
        mounted["/"] = "ext4"
        return mounted, ordered_extra
    end

    for line in f:lines() do
        local dev, mp, fstype = line:match("^(%S+)%s+(%S+)%s+(%S+)")
        if dev and mp and fstype then
            mp = mp:gsub("\\040", " ")
            if mp == "/" or VALID_FS[fstype] then
                -- Ignore system/boot/sandbox/virtual mounts (strictly physical user storage)
                if not mp:match("^/boot")
                   and not mp:match("^/tmp")
                   and not mp:match("^/var")
                   and not mp:match("^/usr")
                   and not mp:match("^/lib")
                   and not mp:match("^/bin")
                   and not mp:match("^/sbin")
                   and not mp:match("^/etc")
                   and not mp:match("^/dev")
                   and not mp:match("^/proc")
                   and not mp:match("^/sys")
                   and not mp:match("^/run/user")
                   and not mp:match("^/home/[^/]+/%.")
                   and not mp:match("^/home/[^/]+/kde_tuning") then
                    if not mounted[mp] then
                        mounted[mp] = fstype
                        if mp ~= "/" then
                            table.insert(ordered_extra, mp)
                        end
                    end
                end
            end
        end
    end
    f:close()
    mounted["/"] = mounted["/"] or "ext4"
    return mounted, ordered_extra
end

-- Cache for discovered disks and filesystem usage
local last_fs_check = 0
local cached_entries = {}

local function get_storage_entries()
    local now = os.time()
    if #cached_entries > 0 and (now - last_fs_check < 3) then
        return cached_entries
    end

    local mounted, ordered_extra = get_active_mounts()
    local user = os.getenv("USER") or os.getenv("LOGNAME") or ""
    if user == "" then
        local home = os.getenv("HOME") or ""
        user = home:match("([^/]+)$") or ""
    end

    local selected = {}
    local used_paths = {}

    local function add_entry(label, path)
        if not path or used_paths[path] then return end
        local perc = tonumber(conky_parse("${fs_used_perc " .. path .. "}")) or 0
        local used = conky_parse("${fs_used " .. path .. "}") or "0B"
        local size = conky_parse("${fs_size " .. path .. "}") or "?"
        local free = conky_parse("${fs_free " .. path .. "}") or "?"
        used_paths[path] = true
        local color_idx = (#selected % #PALETTE) + 1
        table.insert(selected, {
            label = label,
            path = path,
            perc = perc,
            used = used,
            size = size,
            free = free,
            color = PALETTE[color_idx],
        })
    end

    -- 1. Always include Root ("/")
    add_entry("System", "/")

    -- 2. Check preferred named volumes (Desktop layout compatibility)
    local named_volumes = {
        { label = "Personal", path = "/personal", media = "Personal" },
        { label = "Docs",     path = "/documentos", media = "Documentos" },
        { label = "Juegos",   path = "/juegos", media = "Juegos" },
        { label = "Home",     path = "/home", media = "Home" },
        { label = "Data",     path = "/data", media = "Data" },
    }

    for _, vol in ipairs(named_volumes) do
        if #selected >= 4 then break end
        local media_p = (user ~= "") and ("/run/media/" .. user .. "/" .. vol.media) or nil
        if mounted[vol.path] then
            add_entry(vol.label, vol.path)
        elseif media_p and mounted[media_p] then
            add_entry(vol.label, media_p)
        end
    end

    -- 3. Add any other external / removable or secondary partitions found in /proc/mounts
    for _, mp in ipairs(ordered_extra) do
        if #selected >= 4 then break end
        if not used_paths[mp] then
            local name = mp:match("([^/]+)$") or mp
            if #name > 10 then name = name:sub(1, 10) end
            name = name:sub(1, 1):upper() .. name:sub(2)
            add_entry(name, mp)
        end
    end

    cached_entries = selected
    last_fs_check = now
    return cached_entries
end

-- Helper function to draw rounded rectangles
function draw_rounded_rectangle(cr, x, y, w, h, r)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r,     r, -math.pi/2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi/2)
    cairo_arc(cr, x + r,     y + h - r, r, math.pi/2, math.pi)
    cairo_arc(cr, x + r,     y + r,     r, math.pi, -math.pi/2)
    cairo_close_path(cr)
end

-- Function to draw a disk usage bar with label and optional secondary stat
function draw_disk_bar(cr, left_text, right_text, value, x, y, w, h, r, bg_color, fg_color)
    -- Draw background bar
    cairo_new_path(cr)
    cairo_set_source_rgba(cr, bg_color[1], bg_color[2], bg_color[3], bg_color[4])
    draw_rounded_rectangle(cr, x, y, w, h, r)
    cairo_fill(cr)

    -- Draw foreground fill based on usage
    if value > 0 then
        local fill_w = (value / 100) * w
        if fill_w < 2 * r then fill_w = 2 * r end
        if fill_w > w then fill_w = w end
        cairo_new_path(cr)
        cairo_set_source_rgba(cr, fg_color[1], fg_color[2], fg_color[3], fg_color[4])
        draw_rounded_rectangle(cr, x, y, fill_w, h, r)
        cairo_fill(cr)
    end

    -- Draw left label text
    cairo_new_path(cr)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.95)
    cairo_select_font_face(cr, "Abel", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 9.5)
    cairo_move_to(cr, x, y - 6)
    cairo_show_text(cr, left_text)

    -- Draw optional right-aligned stat (e.g. Free space)
    if right_text and right_text ~= "" then
        local ok, ext = pcall(function() return cairo_text_extents_t:create() end)
        if ok and ext then
            cairo_text_extents(cr, right_text, ext)
            cairo_move_to(cr, x + w - (ext.width + ext.x_bearing), y - 6)
            cairo_set_source_rgba(cr, 0.1960, 0.8431, 0.2980, 0.9)
            cairo_show_text(cr, right_text)
        end
    end

    cairo_new_path(cr)
end

-- Main function called by Conky or reused by rings_rounded.lua
function conky_draw_disk_bars(passed_cr)
    if conky_window == nil then return end

    local cr = passed_cr
    local cs = nil
    local need_destroy_cs = false

    if cr == nil then
        if conky_surface ~= nil then
            cs = conky_surface()
        else
            cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                           conky_window.visual, conky_window.width, conky_window.height)
            need_destroy_cs = true
        end
        cr = cairo_create(cs)
    end

    local entries = get_storage_entries()
    local count = #entries
    local bg = {1, 1, 1, 0.12}

    if count == 1 then
        -- 1 Disk (Laptop single partition): perfectly centered hero bar
        local item = entries[1]
        local full_x = 16
        local full_w = 268
        local bar_y = 738
        local bar_h = 16
        local radius = 8

        local left_txt = string.format("%s: %d%% (%s / %s)", item.label, item.perc, item.used, item.size)
        local right_txt = string.format("Free: %s", item.free)
        draw_disk_bar(cr, left_txt, right_txt, item.perc, full_x, bar_y, full_w, bar_h, radius, bg, item.color)

    elseif count == 2 then
        -- 2 Disks: Stacked full-width bars
        local full_x = 16
        local full_w = 268
        local rows_y = { 722, 762 }
        local bar_h = 14
        local radius = 7

        for i, item in ipairs(entries) do
            local left_txt = string.format("%s: %d%% (%s / %s)", item.label, item.perc, item.used, item.size)
            local right_txt = string.format("Free: %s", item.free)
            draw_disk_bar(cr, left_txt, right_txt, item.perc, full_x, rows_y[i], full_w, bar_h, radius, bg, item.color)
        end

    else
        -- 3 or 4 Disks: 2x2 Grid layout (Desktop)
        local col1_x = 16
        local col2_x = 158
        local row1_y = 718
        local row2_y = 760
        local half_w = 126
        local bar_h = 14
        local radius = 7

        local coords = {
            { x = col1_x, y = row1_y },
            { x = col1_x, y = row2_y },
            { x = col2_x, y = row1_y },
            { x = col2_x, y = row2_y },
        }

        for i = 1, math.min(4, count) do
            local item = entries[i]
            local pos = coords[i]
            local txt = string.format("%s: %d%% (%s)", item.label, item.perc, item.size)
            draw_disk_bar(cr, txt, nil, item.perc, pos.x, pos.y, half_w, bar_h, radius, bg, item.color)
        end
    end

    if passed_cr == nil then
        cairo_destroy(cr)
        if need_destroy_cs and cs ~= nil then
            cairo_surface_destroy(cs)
        end
    end
end
