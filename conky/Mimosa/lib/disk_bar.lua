--[==[
	Version		: 2.0
	Author		: Closebox73 (Enhanced for 4 partitions 2x2 grid)
	Description	: Draw multi bar for storage status (System, Personal, Documentos, Juegos)
]==]

require 'cairo'
require 'cairo_xlib'

-- Helper function to check if a path exists
local function path_exists(path)
    if not path or path == "" then return false end
    local ok, _, code = os.rename(path, path)
    if ok or code == 13 or code == 16 then
        return true
    end
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

-- Resolve mount path dynamically
local function get_mount_path(preferred, label)
    if path_exists(preferred) then
        return preferred
    end
    local user = os.getenv("USER") or "dagarciam"
    local media_path = "/run/media/" .. user .. "/" .. label
    if path_exists(media_path) then
        return media_path
    end
    return nil
end

-- Get filesystem usage and total size
local function get_fs_info(preferred, label)
    local p = get_mount_path(preferred, label)
    if not p then
        return 0, "N/A"
    end
    local perc = tonumber(conky_parse("${fs_used_perc " .. p .. "}")) or 0
    local size = conky_parse("${fs_size " .. p .. "}") or "?"
    return perc, size
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

-- Function to draw a disk usage bar with label
function draw_disk_bar(cr, label, value, total, x, y, w, h, r, bg_color, fg_color)
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

    -- Draw label text
    cairo_new_path(cr)
    cairo_set_source_rgba(cr, 1, 1, 1, 1)
    cairo_select_font_face(cr, "Abel", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 9.5)
    cairo_move_to(cr, x, y - 5)
    cairo_show_text(cr, string.format("%s: %d%% (%s)", label, value, total))
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

    -- Get usage values and total sizes
    local root, root_size = get_fs_info("/", "Root")
    local personal, personal_size = get_fs_info("/personal", "Personal")
    local doc, doc_size = get_fs_info("/documentos", "Documentos")
    local juegos, juegos_size = get_fs_info("/juegos", "Juegos")

    -- 2x2 Grid dimensions
    local col1_x = 16
    local col2_x = 158
    local row1_y = 500
    local row2_y = 546

    local width = 126
    local height = 14
    local radius = 7

    -- Colors
    local bg = {1, 1, 1, 0.12}
    local fg_root     = {1.0, 0.2705, 0.2235, 1.0} -- Coral red
    local fg_personal = {0.1960, 0.8431, 0.2980, 1.0} -- Bright green
    local fg_doc      = {0.0, 0.7843, 1.0, 1.0}    -- Cyan
    local fg_juegos   = {1.0, 0.6235, 0.0392, 1.0} -- Amber orange

    -- Column 1: System and Personal
    draw_disk_bar(cr, "System", root, root_size, col1_x, row1_y, width, height, radius, bg, fg_root)
    draw_disk_bar(cr, "Personal", personal, personal_size, col1_x, row2_y, width, height, radius, bg, fg_personal)

    -- Column 2: Documentos and Juegos
    draw_disk_bar(cr, "Docs", doc, doc_size, col2_x, row1_y, width, height, radius, bg, fg_doc)
    draw_disk_bar(cr, "Juegos", juegos, juegos_size, col2_x, row2_y, width, height, radius, bg, fg_juegos)

    if passed_cr == nil then
        cairo_destroy(cr)
        if need_destroy_cs and cs ~= nil then
            cairo_surface_destroy(cs)
        end
    end
end
