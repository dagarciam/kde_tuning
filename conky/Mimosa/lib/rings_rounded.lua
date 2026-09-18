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
    local base_y = 909
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

-- Helper to draw rounded rectangle
local function draw_rounded_rect(cr, x, y, w, h, r)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r,     r, -math.pi/2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi/2)
    cairo_arc(cr, x + r,     y + h - r, r, math.pi/2, math.pi)
    cairo_arc(cr, x + r,     y + r,     r, math.pi, -math.pi/2)
    cairo_close_path(cr)
end

-- Dynamic load color helper
local function get_load_color(val)
    if val >= 80 then
        return 0xff453a -- Coral Red
    elseif val >= 60 then
        return 0xff9f0a -- Amber Orange
    else
        return 0x32d74c -- Bright Green
    end
end

-- Physical core detection table (cached)
local physical_cores = nil

local function get_physical_cores()
    if physical_cores ~= nil then
        return physical_cores
    end

    physical_cores = {}
    local seen_cores = {}

    for cpu_id = 0, 63 do
        local path = string.format('/sys/devices/system/cpu/cpu%d/topology/thread_siblings_list', cpu_id)
        local f = io.open(path, 'r')
        if not f then break end
        local content = (f:read('*all') or ''):gsub('%s+', '')
        f:close()

        local key = content
        if not seen_cores[key] then
            seen_cores[key] = true
            local cpus = {}
            for part in string.gmatch(content, '([^,]+)') do
                local s, e = part:match('^(%d+)%-(%d+)$')
                if s and e then
                    for c = tonumber(s), tonumber(e) do table.insert(cpus, c) end
                else
                    local c = tonumber(part)
                    if c then table.insert(cpus, c) end
                end
            end
            if #cpus == 0 then table.insert(cpus, cpu_id) end
            table.insert(physical_cores, {
                core_num = #physical_cores + 1,
                cpus = cpus
            })
        end
    end

    -- Fallback if sysfs was unavailable
    if #physical_cores == 0 then
        for i = 1, 12 do
            table.insert(physical_cores, { core_num = i, cpus = { i - 1, i - 1 + 12 } })
        end
    end

    return physical_cores
end

-- Calculates average load for a physical core across all its SMT sibling threads
local function get_physical_core_load(core_info)
    local sum = 0
    for _, cpu_idx in ipairs(core_info.cpus) do
        local val = tonumber(conky_parse('${cpu cpu' .. (cpu_idx + 1) .. '}')) or 0
        sum = sum + val
    end
    local avg = math.floor(sum / #core_info.cpus + 0.5)
    if avg < 0 then avg = 0 end
    if avg > 100 then avg = 100 end
    return avg
end

-- Renders the 12 physical cores and total CPU load for Card 3 (AMD Ryzen 9 Dual-CCD architecture)
function draw_cpu_card(cr)
    -- 1. Left: Hero Ring for Total CPU Load
    local xc = 56.0
    local yc = 533.0
    local radius = 26.0
    local thickness = 5.5

    local total_cpu = tonumber(conky_parse('${cpu cpu0}')) or 0
    if total_cpu < 0 then total_cpu = 0 end
    if total_cpu > 100 then total_cpu = 100 end

    local angle_0 = -math.pi / 2
    local angle_f = angle_0 + 2 * math.pi
    local angle_v = angle_0 + (total_cpu / 100.0) * (2 * math.pi)

    -- Background track
    cairo_set_line_width(cr, thickness)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_new_sub_path(cr)
    cairo_arc(cr, xc, yc, radius, angle_0, angle_f)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.12)
    cairo_stroke(cr)

    -- Foreground value arc
    if total_cpu > 0 then
        local fg_col = get_load_color(total_cpu)
        cairo_new_sub_path(cr)
        cairo_arc(cr, xc, yc, radius, angle_0, angle_v)
        cairo_set_source_rgba(cr, rgb_to_r_g_b(fg_col, 0.95))
        cairo_stroke(cr)
    end

    -- Center percentage text
    local total_text = string.format("%d%%", total_cpu)
    cairo_select_font_face(cr, "Bebas Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 16.5)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.95)
    local ok, extents = pcall(function() return cairo_text_extents_t:create() end)
    if ok and extents then
        cairo_text_extents(cr, total_text, extents)
        cairo_move_to(cr, xc - (extents.width / 2 + extents.x_bearing), yc - (extents.height / 2 + extents.y_bearing))
    else
        cairo_move_to(cr, xc - 12, yc + 5)
    end
    cairo_show_text(cr, total_text)

    -- Micro-label under ring: "CPU TOTAL"
    cairo_select_font_face(cr, "Inter", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 8.5)
    cairo_set_source_rgba(cr, 0.1960, 0.8431, 0.2980, 1.0)
    local ok_lbl, ext_lbl = pcall(function() return cairo_text_extents_t:create() end)
    if ok_lbl and ext_lbl then
        cairo_text_extents(cr, "CPU TOTAL", ext_lbl)
        cairo_move_to(cr, xc - (ext_lbl.width / 2 + ext_lbl.x_bearing), yc + 41)
    else
        cairo_move_to(cr, xc - 22, yc + 41)
    end
    cairo_show_text(cr, "CPU TOTAL")

    -- Micro-label under ring: "12 CORES · 24 TH"
    cairo_select_font_face(cr, "Abel", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 7.5)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.6)
    local ok_sub, ext_sub = pcall(function() return cairo_text_extents_t:create() end)
    local sub_txt = "12 CORES · 24 TH"
    if ok_sub and ext_sub then
        cairo_text_extents(cr, sub_txt, ext_sub)
        cairo_move_to(cr, xc - (ext_sub.width / 2 + ext_sub.x_bearing), yc + 53)
    else
        cairo_move_to(cr, xc - 28, yc + 53)
    end
    cairo_show_text(cr, sub_txt)

    -- 2. Right: Dual-CCD Matrix (12 Physical Cores: CCD0 [V-Cache] and CCD1 [Freq])
    local cores = get_physical_cores()

    local col1_x = 112
    local col2_x = 202
    local header_y = 480

    -- Column 1 Header: CCD0 · V-CACHE
    cairo_select_font_face(cr, "Inter", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 8.5)
    cairo_set_source_rgba(cr, 0.1960, 0.8431, 0.2980, 0.95)
    cairo_move_to(cr, col1_x, header_y)
    cairo_show_text(cr, "CCD0 · V-CACHE")

    -- Column 2 Header: CCD1 · FREQ
    cairo_move_to(cr, col2_x, header_y)
    cairo_show_text(cr, "CCD1 · FREQ")

    local y_start = 495
    local row_step = 22
    local bar_w = 38
    local bar_h = 5.5
    local bar_r = 2.75

    for k = 1, 6 do
        local row_y = y_start + (k - 1) * row_step

        -- --- Column 1: Core k (CCD 0) ---
        local c1_idx = k
        if cores[c1_idx] then
            local load1 = get_physical_core_load(cores[c1_idx])
            local lbl1 = string.format("C%02d", c1_idx)

            -- Label
            cairo_select_font_face(cr, "Inter", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
            cairo_set_font_size(cr, 8.0)
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.75)
            cairo_move_to(cr, col1_x, row_y + 6)
            cairo_show_text(cr, lbl1)

            -- Bar track
            local bar1_x = col1_x + 22
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.12)
            draw_rounded_rect(cr, bar1_x, row_y, bar_w, bar_h, bar_r)
            cairo_fill(cr)

            -- Bar fill
            if load1 > 0 then
                local fill1_w = math.max(2 * bar_r, (load1 / 100.0) * bar_w)
                if fill1_w > bar_w then fill1_w = bar_w end
                local col1_fg = get_load_color(load1)
                cairo_set_source_rgba(cr, rgb_to_r_g_b(col1_fg, 0.95))
                draw_rounded_rect(cr, bar1_x, row_y, fill1_w, bar_h, bar_r)
                cairo_fill(cr)
            end

            -- Value text
            local val1_txt = string.format("%d%%", load1)
            cairo_select_font_face(cr, "Abel", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
            cairo_set_font_size(cr, 8.0)
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.85)
            cairo_move_to(cr, bar1_x + bar_w + 5, row_y + 6)
            cairo_show_text(cr, val1_txt)
        end

        -- --- Column 2: Core k+6 (CCD 1) ---
        local c2_idx = k + 6
        if cores[c2_idx] then
            local load2 = get_physical_core_load(cores[c2_idx])
            local lbl2 = string.format("C%02d", c2_idx)

            -- Label
            cairo_select_font_face(cr, "Inter", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
            cairo_set_font_size(cr, 8.0)
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.75)
            cairo_move_to(cr, col2_x, row_y + 6)
            cairo_show_text(cr, lbl2)

            -- Bar track
            local bar2_x = col2_x + 22
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.12)
            draw_rounded_rect(cr, bar2_x, row_y, bar_w, bar_h, bar_r)
            cairo_fill(cr)

            -- Bar fill
            if load2 > 0 then
                local fill2_w = math.max(2 * bar_r, (load2 / 100.0) * bar_w)
                if fill2_w > bar_w then fill2_w = bar_w end
                local col2_fg = get_load_color(load2)
                cairo_set_source_rgba(cr, rgb_to_r_g_b(col2_fg, 0.95))
                draw_rounded_rect(cr, bar2_x, row_y, fill2_w, bar_h, bar_r)
                cairo_fill(cr)
            end

            -- Value text
            local val2_txt = string.format("%d%%", load2)
            cairo_select_font_face(cr, "Abel", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
            cairo_set_font_size(cr, 8.0)
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.85)
            cairo_move_to(cr, bar2_x + bar_w + 5, row_y + 6)
            cairo_show_text(cr, val2_txt)
        end
    end

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

    -- 4. Draw 12 physical cores and CPU load card
    draw_cpu_card(cr)

    cairo_destroy(cr)
    if need_destroy_cs and cs ~= nil then
        cairo_surface_destroy(cs)
    end
end

function conky_system_rings()
    conky_main_draw()
end
