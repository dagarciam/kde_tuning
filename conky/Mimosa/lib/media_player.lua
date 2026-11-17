--[==[
    Conky Mimosa - Media Player Lua Module
    Features:
    - In-memory state reading from /tmp/conky_media_state (zero subshells / zero blocking)
    - Precise frame-based 250ms state updates (eliminating CPU-time os.clock throttling)
    - Classic LP vinyl turntable disc rotation at constant 33⅓ RPM (0.1745 rad/frame at 20 FPS)
    - Material You / Android Auto fluid squiggly progress bar
    - Conky text helper functions (conky_media_artist, conky_media_title, etc.)
]==]

require 'cairo'
require 'cairo_xlib'
require 'cairo_imlib2_helper'

local media_state = {
    status = "Stopped",
    artist = "Media Player",
    title = "No music playing",
    album = "",
    time = "Idle",
    icon = "",
    arturl = "",
    perc = 0
}

local frame_counter = 0
local wave_phase = 0
local vinyl_angle = 0

-- Unescape basic shell escaping
local function unescape_val(str)
    if not str then return "" end
    local s = str:gsub("^'", ""):gsub("'$", ""):gsub('^"', ''):gsub('"$', '')
    s = s:gsub("\\(.)", "%1")
    return s
end

-- Non-blocking state reader: runs every 5 frames (~250ms of real wall-clock time at 20 FPS)
local function update_media_state(force)
    if not force then
        frame_counter = frame_counter + 1
        if frame_counter % 5 ~= 0 and frame_counter > 1 then
            return
        end
    end

    local f = io.open('/tmp/conky_media_state', 'r')
    if not f then return end

    for line in f:lines() do
        local k, v = line:match("^PCTL_([%w_]+)=(.+)$")
        if k and v then
            local clean_v = unescape_val(v)
            if k == "STATUS" then media_state.status = clean_v
            elseif k == "ARTIST" then media_state.artist = clean_v
            elseif k == "TITLE" then media_state.title = clean_v
            elseif k == "ALBUM" then media_state.album = clean_v
            elseif k == "TIME" then media_state.time = clean_v
            elseif k == "ICON" then media_state.icon = clean_v
            elseif k == "ARTURL" then media_state.arturl = clean_v
            elseif k == "PERC" then media_state.perc = tonumber(clean_v) or 0
            end
        end
    end
    f:close()
end

-- Exported helper functions for Conky text evaluation (${lua media_artist}, etc.)
function conky_media_status() update_media_state(false); return media_state.status end
function conky_media_artist() update_media_state(false); return media_state.artist end
function conky_media_title()  update_media_state(false); return media_state.title end
function conky_media_album()  update_media_state(false); return media_state.album end
function conky_media_time()   update_media_state(false); return media_state.time end
function conky_media_icon()   update_media_state(false); return media_state.icon end
function conky_media_perc()   update_media_state(false); return tostring(media_state.perc) end

-- Material You / Android Auto squiggly wave media progress bar
local function draw_media_wave_bar(cr, log_f)
    if media_state.status == "" or media_state.status == "Stopped" then
        return
    end

    local perc = media_state.perc or 0
    if perc < 0 then perc = 0 end
    if perc > 100 then perc = 100 end

    local x1 = 18
    local x2 = 282
    local base_y = 106.0 -- relative to card top
    local curr_x = x1 + (perc / 100.0) * (x2 - x1)

    -- 1. Unplayed portion (straight subtle track from thumb to end)
    if curr_x < x2 then
        cairo_new_path(cr)
        cairo_set_line_width(cr, 2.5)
        if CAIRO_LINE_CAP_ROUND then cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND) end
        cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.18)
        cairo_move_to(cr, curr_x, base_y)
        cairo_line_to(cr, x2, base_y)
        cairo_stroke(cr)
    end

    -- 2. Played portion (Material You wavy line when playing, flat when paused)
    if curr_x > x1 then
        cairo_new_path(cr)
        cairo_set_line_width(cr, 2.8)
        if CAIRO_LINE_CAP_ROUND then cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND) end
        if CAIRO_LINE_JOIN_ROUND then cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND) end
        cairo_set_source_rgba(cr, 0.1960, 0.8431, 0.2980, 1.0) -- Accent Green (#32d74c)

        if media_state.status == "Playing" and (curr_x - x1) > 8 then
            wave_phase = (wave_phase + 0.10) % (2 * math.pi)
            local wavelength = 16.0
            local amplitude = 2.4

            cairo_move_to(cr, x1, base_y)
            for x = x1 + 1, curr_x do
                local taper_start = math.min(1.0, (x - x1) / 8.0)
                local taper_end = math.min(1.0, (curr_x - x) / 8.0)
                local env = taper_start * taper_end
                local wy = base_y + env * amplitude * math.sin((x - x1) * 2 * math.pi / wavelength - wave_phase)
                cairo_line_to(cr, x, wy)
            end
            cairo_stroke(cr)
        else
            cairo_move_to(cr, x1, base_y)
            cairo_line_to(cr, curr_x, base_y)
            cairo_stroke(cr)
        end
    end

    -- 3. Thumb indicator (clean white dot)
    cairo_new_path(cr)
    cairo_arc(cr, curr_x, base_y, 3.8, 0, 2 * math.pi)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 1.0)
    cairo_fill(cr)
end

-- Renders the rotating classic vinyl LP disc at exactly 33.33 RPM
local function draw_media_vinyl(cr, log_f)
    local xc = 52.0
    local yc = 57.0 -- relative to card top (card starts at 0, disc center at 57)
    local size = 68.0

    if media_state.status == "Playing" then
        vinyl_angle = (vinyl_angle + 0.1745329) % (2 * math.pi)
    elseif media_state.status == "Stopped" or media_state.status == "" then
        vinyl_angle = 0
    end

    local cover_file = "/tmp/conky_cover.png"
    local f = io.open(cover_file, "r")
    if f then
        f:close()
    else
        local user = os.getenv("USER") or "dagarciam"
        cover_file = "/home/" .. user .. "/.config/conky/Mimosa/assets/default_cover.png"
    end

    if log_f then
        log_f:write(string.format("vinyl: xc=%f, yc=%f, size=%f, angle=%f, cover=%s\n",
            xc, yc, size, vinyl_angle, cover_file))
    end

    -- Draw rotated vinyl record using Cairo
    local drawn = false
    local surf = cairo_image_surface_create_from_png(cover_file)
    if surf then
        local s_status = cairo_surface_status(surf)
        if s_status == 0 then
            local img_w = cairo_image_surface_get_width(surf)
            local img_h = cairo_image_surface_get_height(surf)
            if img_w > 0 and img_h > 0 then
                cairo_save(cr)
                cairo_translate(cr, xc, yc)
                cairo_rotate(cr, vinyl_angle)
                cairo_scale(cr, size / img_w, size / img_h)
                cairo_set_source_surface(cr, surf, -img_w / 2, -img_h / 2)
                cairo_paint(cr)
                cairo_restore(cr)
                drawn = true
            end
        end
        cairo_surface_destroy(surf)
    end

    if not drawn and cairo_place_image then
        cairo_save(cr)
        cairo_translate(cr, xc, yc)
        cairo_rotate(cr, vinyl_angle)
        cairo_place_image(cover_file, cr, math.floor(-size / 2), math.floor(-size / 2), math.floor(size), math.floor(size), 1.0)
        cairo_restore(cr)
        drawn = true
    end
    if log_f then log_f:write("vinyl: finished cairo_place_image\n") end
end

-- Main draw hook for Mimosa-media.conf
function conky_media_player_draw()
    local log_f = io.open('/tmp/conky_media_debug.log', 'w')
    if log_f then
        log_f:write(string.format("conky_window = %s\n", tostring(conky_window)))
        if conky_window then
            log_f:write(string.format("display=%s, drawable=%s, visual=%s, width=%s, height=%s\n",
                tostring(conky_window.display), tostring(conky_window.drawable),
                tostring(conky_window.visual), tostring(conky_window.width), tostring(conky_window.height)))
        end
    end

    if conky_window == nil then 
        if log_f then log_f:write("conky_window is nil, returning\n"); log_f:close() end
        return 
    end

    update_media_state(false)

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, conky_window.width, conky_window.height)
    local need_destroy_cs = true

    if cs == nil then
        if log_f then log_f:write("cs is nil!\n"); log_f:close() end
        return
    end

    local cr = cairo_create(cs)
    if cr == nil then
        if log_f then log_f:write("cr is nil!\n"); log_f:close() end
        return
    end

    -- 1. Draw Android Auto style wavy media progress bar
    local ok_wave, err_wave = pcall(draw_media_wave_bar, cr, log_f)
    if log_f then log_f:write(string.format("draw_media_wave_bar: ok=%s, err=%s\n", tostring(ok_wave), tostring(err_wave))) end

    -- 2. Draw Rotating Vinyl Disc at 33.33 RPM
    local ok_vinyl, err_vinyl = pcall(draw_media_vinyl, cr, log_f)
    if log_f then log_f:write(string.format("draw_media_vinyl: ok=%s, err=%s\n", tostring(ok_vinyl), tostring(err_vinyl))) end

    cairo_destroy(cr)
    if need_destroy_cs and cs ~= nil then
        cairo_surface_destroy(cs)
    end
    if log_f then log_f:write("Draw finished successfully\n"); log_f:close() end
end

