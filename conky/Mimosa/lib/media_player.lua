--[==[
    Conky Mimosa - Media Player Lua Module
    Features:
    - In-memory state reading from /tmp/conky_media_state (zero subshells / zero blocking)
    - Classic LP vinyl turntable disc rotation at exactly 33⅓ RPM (3.49 rad/sec)
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

local last_state_read_time = 0
local wave_phase = 0
local vinyl_angle = 0
local last_vinyl_frame_time = 0

-- Unescape basic shell escaping
local function unescape_val(str)
    if not str then return "" end
    local s = str:gsub("^'", ""):gsub("'$", ""):gsub('^"', ''):gsub('"$', '')
    s = s:gsub("\\'", "'"):gsub('\\"', '"'):gsub("\\\\", "\\")
    return s
end

-- Non-blocking state reader with 250ms throttle
local function update_media_state()
    local now_clock = os.clock()
    if (now_clock - last_state_read_time < 0.25) and last_state_read_time > 0 then
        return
    end
    last_state_read_time = now_clock

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
function conky_media_status() update_media_state(); return media_state.status end
function conky_media_artist() update_media_state(); return media_state.artist end
function conky_media_title()  update_media_state(); return media_state.title end
function conky_media_album()  update_media_state(); return media_state.album end
function conky_media_time()   update_media_state(); return media_state.time end
function conky_media_icon()   update_media_state(); return media_state.icon end
function conky_media_perc()   update_media_state(); return tostring(media_state.perc) end

-- Material You / Android Auto squiggly wave bar
local function draw_media_wave_bar(cr)
    if media_state.status == "" or media_state.status == "Stopped" then
        return
    end

    local perc = media_state.perc or 0
    if perc < 0 then perc = 0 end
    if perc > 100 then perc = 100 end

    local x1 = 18
    local x2 = 282
    local base_y = 106.0 -- relative to card top (Card 5 height 122)
    local curr_x = x1 + (perc / 100.0) * (x2 - x1)

    -- 1. Unplayed portion (straight subtle track)
    cairo_new_path(cr)
    cairo_set_line_width(cr, 2.5)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.18)
    if curr_x < x2 then
        cairo_move_to(cr, curr_x, base_y)
        cairo_line_to(cr, x2, base_y)
        cairo_stroke(cr)
    end

    -- 2. Played portion (Material You wavy line when playing, flat when paused)
    local fg_color = {0.1960, 0.8431, 0.2980, 1.0} -- Accent Green (#32d74c)
    cairo_set_source_rgba(cr, fg_color[1], fg_color[2], fg_color[3], fg_color[4])
    cairo_set_line_width(cr, 2.8)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)

    if curr_x > x1 then
        cairo_new_path(cr)
        if media_state.status == "Playing" and (curr_x - x1) > 8 then
            -- Fluid wave animation synced with frame rate
            wave_phase = (wave_phase + 0.08) % (2 * math.pi)
            local wavelength = 16.0
            local amplitude = 2.4

            cairo_move_to(cr, x1, base_y)
            for x = x1 + 1, curr_x do
                local taper_start = math.min(1.0, (x - x1) / 8.0)
                local taper_end = math.min(1.0, (curr_x - x) / 8.0)
                local env = taper_start * taper_end
                local wy = base_y + env * amplitude * math.sin((x - x1) * 2 * math.pi / wavelength + wave_phase)
                cairo_line_to(cr, x, wy)
            end
            cairo_stroke(cr)
        else
            -- Flat line when paused or very short
            cairo_move_to(cr, x1, base_y)
            cairo_line_to(cr, curr_x, base_y)
            cairo_stroke(cr)
        end

        -- 3. Thumb indicator (rounded pill/dot)
        cairo_new_sub_path(cr)
        cairo_arc(cr, curr_x, base_y, 3.8, 0, 2 * math.pi)
        cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 1.0)
        cairo_fill(cr)
    end
    cairo_new_path(cr)
end

-- Renders the rotating classic vinyl LP disc at exactly 33.33 RPM
local function draw_media_vinyl(cr)
    local xc = 52.0
    local yc = 57.0 -- relative to card top (card starts at 0, disc center at 57)
    local size = 68.0

    local now_clock = os.clock()
    local dt = 0.05
    if last_vinyl_frame_time > 0 then
        dt = now_clock - last_vinyl_frame_time
        if dt > 0.5 or dt <= 0 then dt = 0.05 end
    end
    last_vinyl_frame_time = now_clock

    -- 33.333 RPM = 200 deg/sec = 3.4906585 rad/sec
    if media_state.status == "Playing" then
        local angular_speed = 3.4906585
        vinyl_angle = (vinyl_angle + angular_speed * dt) % (2 * math.pi)
    elseif media_state.status == "Stopped" or media_state.status == "" then
        vinyl_angle = 0
    end
    -- When Paused, vinyl_angle remains frozen in place

    -- Draw rotated vinyl record using Cairo
    cairo_save(cr)
    cairo_translate(cr, xc, yc)
    cairo_rotate(cr, vinyl_angle)
    cairo_place_image("/tmp/conky_cover.png", cr, -size / 2, -size / 2, size, size, 1.0)
    cairo_restore(cr)
end

-- Main draw hook for Mimosa-media.conf
function conky_media_player_draw()
    if conky_window == nil then return end

    update_media_state()

    local cs = nil
    local need_destroy_cs = false

    if conky_surface ~= nil then
        cs = conky_surface()
    else
        cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                       conky_window.visual, conky_window.width, conky_window.height)
        need_destroy_cs = true
    end

    local cr = cairo_create(cs)

    -- 1. Draw Android Auto style wavy media progress bar
    draw_media_wave_bar(cr)

    -- 2. Draw Rotating Vinyl Disc at 33.33 RPM
    draw_media_vinyl(cr)

    cairo_destroy(cr)
    if need_destroy_cs and cs ~= nil then
        cairo_surface_destroy(cs)
    end
end
