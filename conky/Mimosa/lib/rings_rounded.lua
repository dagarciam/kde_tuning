--[==[
	Version		: 1.3
	Author		: Closebox73
	Description	: system_rings.lua: 4 rings for CPU, RAM, GPU, and Temperature
]==]

require 'cairo'
require 'cairo_xlib'

-- Ring configuration table
system_rings = {
    {
        name = 'memperc',
        arg = '',
        max = 100,
        x = 49.5, y = 340.0,
        radius = 25,
        thickness = 6.5,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xffffff,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true,
        dynamic_color = true,
        icon = '', -- Hack Nerd Font: fa-memory (\uefc5)
        icon_size = 17,
        label = 'RAM',
    },
    {
        name = 'vram',
        arg = '',
        max = 100,
        x = 119.7, y = 340.0,
        radius = 25,
        thickness = 6.5,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xffffff,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true,
        dynamic_color = true,
        icon = '󰢮', -- Hack Nerd Font: md-video_vintage / expansion card with memory (\U000f08ae)
        icon_size = 19,
        label = 'VRAM',
        custom_val = function()
            local f = io.open('/sys/class/drm/card1/device/mem_info_vram_used', 'r')
            if f then
                local used = tonumber(f:read('*all') or '0') or 0
                f:close()
                return math.min(100, math.floor((used * 100) / 17095983104 + 0.5))
            end
            return 0
        end,
    },
    {
        name = 'execi',
        arg = '2 cat /sys/class/drm/card1/device/gpu_busy_percent',
        max = 100,
        x = 190.0, y = 340.0,
        radius = 25,
        thickness = 6.5,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xFFFFFF,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true,
        dynamic_color = true,
        icon = '󰾲', -- Hack Nerd Font: md-expansion_card_variant (\U000f0fb2)
        icon_size = 21,
        label = 'GPU',
    },
    {
        name = 'hwmon',
        arg = '2 temp 1',
        max = 100,
        x = 259.5, y = 340.0,
        radius = 25,
        thickness = 6.5,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xFFFFFF,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true,
        dynamic_color = true,
        icon = '', -- Hack Nerd Font: fa-thermometer_half (\uf2c9)
        icon_size = 17,
        label = 'TEMP',
    }
}

-- Converts hex color to normalized RGBA components
function rgb_to_r_g_b(colour, alpha)
	return ((colour / 0x10000) % 0x100) / 255.,
	       ((colour / 0x100) % 0x100) / 255.,
	       (colour % 0x100) / 255.,
	       alpha
end

-- Draws a single ring with background and foreground arcs
function draw_system_ring(cr, ring, value)
    local angle_0 = (ring.start_angle or 0) * math.pi/180 - math.pi/2
    local angle_f = (ring.end_angle or 360) * math.pi/180 - math.pi/2
    local angle_v = angle_0 + (angle_f - angle_0) * (value / ring.max)

    -- Dynamic thermal/load color calculation
    local fg_col = ring.fg_color
    if ring.dynamic_color then
        if value >= 80 then
            fg_col = 0xff453a -- High load / Temp warning: Coral Red
        elseif value >= 60 then
            fg_col = 0xff9f0a -- Medium load: Amber Orange
        else
            fg_col = ring.fg_color or 0x32d74c -- Normal: Bright Green
        end
    end

    cairo_set_line_width(cr, ring.thickness)
    cairo_set_line_cap(cr, ring.rounded and CAIRO_LINE_CAP_ROUND or CAIRO_LINE_CAP_BUTT)

    -- Draw background arc
    cairo_new_sub_path(cr)
    cairo_arc(cr, ring.x, ring.y, ring.radius, angle_0, angle_f)
    cairo_set_source_rgba(cr, rgb_to_r_g_b(ring.bg_color, ring.bg_alpha))
    cairo_stroke(cr)

    -- Draw foreground arc representing the value
    if value > 0 then
        cairo_new_sub_path(cr)
        cairo_arc(cr, ring.x, ring.y, ring.radius, angle_0, angle_v)
        cairo_set_source_rgba(cr, rgb_to_r_g_b(fg_col, ring.fg_alpha))
        cairo_stroke(cr)
    end

    -- Draw unified icon cleanly in center
    if ring.icon then
        cairo_select_font_face(cr, "Hack Nerd Font", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, ring.icon_size or 18)
        cairo_set_source_rgba(cr, 1, 1, 1, 1) -- White

        local ok, extents = pcall(function() return cairo_text_extents_t:create() end)
        if ok and extents then
            cairo_text_extents(cr, ring.icon, extents)
            local move_x = ring.x - (extents.width / 2 + extents.x_bearing)
            local move_y = ring.y - (extents.height / 2 + extents.y_bearing)
            cairo_move_to(cr, move_x, move_y)
        else
            cairo_move_to(cr, ring.x - (ring.icon_size or 18) / 2, ring.y + (ring.icon_size or 18) / 3)
        end
        cairo_show_text(cr, ring.icon)
    end

    -- Draw clean micro-label under ring (RAM, VRAM, GPU, TEMP)
    if ring.label then
        cairo_select_font_face(cr, "Inter", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(cr, 10.5)
        cairo_set_source_rgba(cr, 0.1960, 0.8431, 0.2980, 1.0)
        local ok, extents = pcall(function() return cairo_text_extents_t:create() end)
        if ok and extents then
            cairo_text_extents(cr, ring.label, extents)
            cairo_move_to(cr, ring.x - (extents.width / 2 + extents.x_bearing), ring.y + 36)
        else
            cairo_move_to(cr, ring.x - 12, ring.y + 36)
        end
        cairo_show_text(cr, ring.label)
    end

    -- Reset path so current text point does not connect to subsequent arcs
    cairo_new_path(cr)
end

-- Android Auto / Material You squiggly progress bar
local wave_phase = 0

function draw_media_wave_bar(cr)
    local status = conky_parse("${execi 1 ~/.config/conky/Mimosa/scripts/playerctl-info.sh -s}") or ""
    if status == "" or status == "Stopped" then
        return
    end

    local perc = tonumber(conky_parse("${execi 1 ~/.config/conky/Mimosa/scripts/playerctl-info.sh -perc}")) or 0
    if perc < 0 then perc = 0 end
    if perc > 100 then perc = 100 end

    local x1 = 18
    local x2 = 282
    local base_y = 904
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
    local fg_color = {0.1960, 0.8431, 0.2980, 1.0} -- Material Accent Green (#32d74c)
    cairo_set_source_rgba(cr, fg_color[1], fg_color[2], fg_color[3], fg_color[4])
    cairo_set_line_width(cr, 2.8)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)

    if curr_x > x1 then
        cairo_new_path(cr)
        if status == "Playing" and (curr_x - x1) > 8 then
            -- Animate phase when playing
            wave_phase = (wave_phase + 0.4) % (2 * math.pi)
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

        -- 3. Thumb indicator (Material You rounded pill/dot)
        cairo_new_sub_path(cr)
        cairo_arc(cr, curr_x, base_y, 3.8, 0, 2 * math.pi)
        cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 1.0)
        cairo_fill(cr)
    end
    cairo_new_path(cr)
end

-- Concentric multi-core CPU dial for Card 3 (inspired by LSD conky)
function draw_cpu_concentric_dial(cr)
    local xc = 68.0
    local yc = 535.0

    -- Detect active online CPUs (0 to count-1)
    local count = 6
    local f = io.open('/sys/devices/system/cpu/online', 'r')
    if f then
        local line = f:read('*all') or ''
        f:close()
        local last = line:match('%-(%d+)')
        if last then
            count = tonumber(last) + 1
        end
    end

    local max_r = 38.0
    local min_r = 18.0
    local step = (max_r - min_r) / math.max(1, count - 1)
    local thickness = math.max(1.8, math.min(3.0, step * 0.65))

    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)

    for i = 1, count do
        local r = max_r - (i - 1) * step
        local val = tonumber(conky_parse('${cpu cpu' .. i .. '}')) or 0
        if val < 0 then val = 0 end
        if val > 100 then val = 100 end

        local angle_0 = -math.pi / 2
        local angle_f = angle_0 + 2 * math.pi
        local angle_v = angle_0 + (val / 100.0) * (2 * math.pi)

        -- Background track
        cairo_set_line_width(cr, thickness)
        cairo_new_sub_path(cr)
        cairo_arc(cr, xc, yc, r, angle_0, angle_f)
        cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.12)
        cairo_stroke(cr)

        -- Foreground value arc
        if val > 0 then
            local fg_col = 0x32d74c
            if val >= 80 then
                fg_col = 0xff453a
            elseif val >= 60 then
                fg_col = 0xff9f0a
            end

            cairo_new_sub_path(cr)
            cairo_arc(cr, xc, yc, r, angle_0, angle_v)
            cairo_set_source_rgba(cr, rgb_to_r_g_b(fg_col, 0.95))
            cairo_stroke(cr)
        end
    end

    -- Center CPU total percentage
    local total_cpu = tonumber(conky_parse('${cpu cpu0}')) or 0
    local text = string.format("%d%%", total_cpu)
    cairo_select_font_face(cr, "Abel", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 12.0)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.95)

    local ok, extents = pcall(function() return cairo_text_extents_t:create() end)
    if ok and extents then
        cairo_text_extents(cr, text, extents)
        local move_x = xc - (extents.width / 2 + extents.x_bearing)
        local move_y = yc - (extents.height / 2 + extents.y_bearing)
        cairo_move_to(cr, move_x, move_y)
    else
        cairo_move_to(cr, xc - 12, yc + 5)
    end
    cairo_show_text(cr, text)

    -- Sub-label under dial (e.g. "6 CORES")
    local lbl = string.format("%d CORES", count)
    cairo_select_font_face(cr, "Abel", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 8.5)
    cairo_set_source_rgba(cr, 0.1960, 0.8431, 0.2980, 0.9)
    local ok2, extents2 = pcall(function() return cairo_text_extents_t:create() end)
    if ok2 and extents2 then
        cairo_text_extents(cr, lbl, extents2)
        cairo_move_to(cr, xc - (extents2.width / 2 + extents2.x_bearing), yc + 46)
    else
        cairo_move_to(cr, xc - 16, yc + 46)
    end
    cairo_show_text(cr, lbl)

    cairo_new_path(cr)
end

-- Main function called by Conky
function conky_main_draw()
    if conky_window == nil then return end

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

    -- 1. Draw storage bars from disk_bar.lua reusing the same Cairo context
    if conky_draw_disk_bars then
        conky_draw_disk_bars(cr)
    end

    -- 2. Loop through all rings and draw them
    for i, ring in ipairs(system_rings) do
        local val = 0
        if ring.custom_val then
            val = ring.custom_val()
        else
            val = tonumber(conky_parse('${' .. ring.name .. ' ' .. ring.arg .. '}')) or 0
        end
        draw_system_ring(cr, ring, val)
    end

    -- 3. Draw Android Auto style wavy media progress bar
    draw_media_wave_bar(cr)

    -- 4. Draw multi-core concentric CPU dial (Card 2)
    draw_cpu_concentric_dial(cr)

    cairo_destroy(cr)
    if need_destroy_cs and cs ~= nil then
        cairo_surface_destroy(cs)
    end
end

function conky_system_rings()
    conky_main_draw()
end
