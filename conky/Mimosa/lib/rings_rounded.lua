--[==[
	Version		: 2.0
	Author		: Closebox73 (Adaptive Multi-Hardware Edition)
	Description	: Dynamic system rings (RAM, Battery/VRAM, GPU, Temp)
	              and adaptive CPU topology matrix (Desktop & Laptop).
]==]

require 'cairo'
require 'cairo_xlib'
require 'cairo_imlib2_helper'

-- Helper to read first line or number from a file without spawning shells
local function read_file_str(path)
    if not path or path == "" then return nil end
    local f = io.open(path, "r")
    if not f then return nil end
    local line = f:read("*line")
    f:close()
    if line then
        return (line:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    return nil
end

local function read_file_num(path)
    local s = read_file_str(path)
    return s and tonumber(s) or nil
end

-- Physical core detection table (cached)
local physical_cores = nil
local logical_thread_count = nil

local function get_physical_cores()
    if physical_cores ~= nil then
        return physical_cores, logical_thread_count
    end

    physical_cores = {}
    local seen_cores = {}
    local total_threads = 0

    for cpu_id = 0, 127 do
        local path = string.format('/sys/devices/system/cpu/cpu%d/topology/thread_siblings_list', cpu_id)
        local content = read_file_str(path)
        if not content then break end
        total_threads = total_threads + 1

        local key = content:gsub('%s+', '')
        if not seen_cores[key] then
            seen_cores[key] = true
            local cpus = {}
            for part in string.gmatch(key, '([^,]+)') do
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
        total_threads = 8
        for i = 1, 4 do
            table.insert(physical_cores, { core_num = i, cpus = { i - 1 } })
        end
    end

    logical_thread_count = total_threads
    return physical_cores, logical_thread_count
end

-- Hardware profile loader (uses lib/hw_config.lua if generated, or pure-Lua fallback)
local hw_profile = nil

local function get_hw_profile()
    if hw_profile ~= nil then
        return hw_profile
    end

    local home = os.getenv("HOME") or ""
    local candidates = {
        home .. "/.config/conky/Mimosa/lib/hw_config.lua",
        "conky/Mimosa/lib/hw_config.lua",
    }
    for _, cfg_path in ipairs(candidates) do
        local f = io.open(cfg_path, "r")
        if f then
            f:close()
            local ok, loaded = pcall(dofile, cfg_path)
            if ok and type(loaded) == "table" then
                hw_profile = loaded
                break
            end
        end
    end

    if not hw_profile then
        hw_profile = {}
    end

    local cores, threads = get_physical_cores()
    hw_profile.physical_cores = hw_profile.physical_cores or #cores
    hw_profile.logical_threads = hw_profile.logical_threads or threads

    -- Fallback CPU name detection from /proc/cpuinfo
    if not hw_profile.cpu_name or hw_profile.cpu_name == "" then
        local cpu_name = "PROCESSOR"
        local f = io.open("/proc/cpuinfo", "r")
        if f then
            for line in f:lines() do
                local m = line:match("^model name%s*:%s*(.+)$")
                if m then
                    cpu_name = m
                        :gsub("%([Rr]%)", "")
                        :gsub("%([Tt][Mm]%)", "")
                        :gsub("%d+th Gen ", "")
                        :gsub("%d+%-Core Processor", "")
                        :gsub("Processor", "")
                        :gsub("CPU", "")
                        :gsub("with .*", "")
                        :gsub("w/ .*", "")
                        :gsub("@.*", "")
                        :gsub("^AMD ", "")
                        :gsub("%s+", " ")
                        :gsub("^%s+", "")
                        :gsub("%s+$", "")
                        :upper()
                    if #cpu_name > 20 then
                        cpu_name = cpu_name:sub(1, 20)
                    end
                    break
                end
            end
            f:close()
        end
        hw_profile.cpu_name = cpu_name
        hw_profile.is_x3d = (cpu_name:find("X3D", 1, true) ~= nil)
    end

    -- Fallback battery detection
    if hw_profile.has_battery == nil then
        for _, bat in ipairs({ "BAT0", "BAT1", "BAT" }) do
            if read_file_str("/sys/class/power_supply/" .. bat .. "/capacity") then
                hw_profile.has_battery = true
                hw_profile.battery_dev = bat
                break
            end
        end
        if hw_profile.has_battery == nil then
            hw_profile.has_battery = false
            hw_profile.battery_dev = ""
        end
    end

    -- Fallback DRM / VRAM detection
    if not hw_profile.drm_card_dir or hw_profile.drm_card_dir == "" then
        local best_vram = 0
        for idx = 0, 3 do
            local cdir = "/sys/class/drm/card" .. idx
            local vtot = read_file_num(cdir .. "/device/mem_info_vram_total")
            if vtot and vtot > best_vram then
                best_vram = vtot
                hw_profile.drm_card_dir = cdir
                hw_profile.drm_card_path = cdir .. "/device"
                hw_profile.vram_total = vtot
                hw_profile.gpu_driver = "amdgpu"
            elseif not hw_profile.drm_card_dir and read_file_str(cdir .. "/device/vendor") then
                hw_profile.drm_card_dir = cdir
                hw_profile.drm_card_path = cdir .. "/device"
                hw_profile.vram_total = 0
                hw_profile.gpu_driver = "intel"
            end
        end
    end

    -- Fallback hwmon detection
    if not hw_profile.cpu_temp_path or hw_profile.cpu_temp_path == "" then
        local fallback_t = nil
        for idx = 0, 12 do
            local hdir = "/sys/class/hwmon/hwmon" .. idx
            local hname = read_file_str(hdir .. "/name")
            local t1 = hdir .. "/temp1_input"
            if hname and read_file_str(t1) then
                if hname == "k10temp" or hname == "zenpower" or hname == "coretemp" or hname == "cpu_thermal" then
                    hw_profile.cpu_temp_path = hw_profile.cpu_temp_path or t1
                elseif hname == "amdgpu" or hname == "radeon" or hname == "nouveau" then
                    hw_profile.gpu_temp_path = hw_profile.gpu_temp_path or t1
                elseif not fallback_t then
                    fallback_t = t1
                end
            end
        end
        hw_profile.cpu_temp_path = hw_profile.cpu_temp_path or fallback_t or "/sys/class/thermal/thermal_zone0/temp"
        hw_profile.gpu_temp_path = hw_profile.gpu_temp_path or fallback_t or hw_profile.cpu_temp_path
    end

    return hw_profile
end

-- ==============================================================================
-- Live Sensor Sampling (1 Hz cached for both Cairo rings and Conky text labels)
-- ==============================================================================
local last_sample_time = 0
local live_metrics = {
    ram_perc = 0,
    ram_text = "0.0G",
    ring2_perc = 0,
    ring2_text = "0%",
    ring2_label = "VRAM",
    ring2_icon = "󰢮",
    ring2_invert = false,
    gpu_perc = 0,
    gpu_text = "0%",
    temp_perc = 0,
    temp_text = "0°C",
    cpu_temp_text = "0°C",
}

local function read_temp_celsius(path)
    local raw = read_file_num(path)
    if not raw then return 0 end
    if raw > 1000 then
        return math.floor(raw / 1000 + 0.5)
    end
    return math.floor(raw + 0.5)
end

local function update_live_metrics()
    local now = os.time()
    if (now - last_sample_time < 1) and last_sample_time > 0 then
        return live_metrics
    end
    last_sample_time = now

    local hw = get_hw_profile()

    -- 1. RAM usage & Swap from /proc/meminfo
    local mem_total, mem_avail, swap_total, swap_free = 0, 0, 0, 0
    local f_mem = io.open("/proc/meminfo", "r")
    if f_mem then
        for line in f_mem:lines() do
            local k, v = line:match("^([%w_]+):%s*(%d+)")
            if k == "MemTotal" then mem_total = tonumber(v) or 0
            elseif k == "MemAvailable" then mem_avail = tonumber(v) or 0
            elseif k == "SwapTotal" then swap_total = tonumber(v) or 0
            elseif k == "SwapFree" then swap_free = tonumber(v) or 0
            end
        end
        f_mem:close()
    end
    if mem_total > 0 then
        local used_kb = math.max(0, mem_total - mem_avail)
        live_metrics.ram_perc = math.min(100, math.floor((used_kb * 100) / mem_total + 0.5))
        live_metrics.ram_text = string.format("%.1fG", used_kb / 1048576)
    end

    -- 2. Ring 2: Battery (if laptop) OR Dedicated VRAM OR Swap
    if hw.has_battery and hw.battery_dev and hw.battery_dev ~= "" then
        local bpath = "/sys/class/power_supply/" .. hw.battery_dev
        local cap = read_file_num(bpath .. "/capacity") or 0
        local status = read_file_str(bpath .. "/status") or ""
        cap = math.max(0, math.min(100, cap))

        live_metrics.ring2_perc = cap
        live_metrics.ring2_label = "BAT"
        live_metrics.ring2_invert = true
        if status == "Charging" then
            live_metrics.ring2_icon = "󰂄"
            live_metrics.ring2_text = string.format("%d%%+", cap)
        else
            live_metrics.ring2_icon = "󰁹"
            live_metrics.ring2_text = string.format("%d%%", cap)
        end
    elseif hw.vram_total and hw.vram_total > 0 and hw.drm_card_path then
        local used = read_file_num(hw.drm_card_path .. "/mem_info_vram_used") or 0
        local tot = hw.vram_total
        live_metrics.ring2_perc = math.min(100, math.floor((used * 100) / tot + 0.5))
        live_metrics.ring2_label = "VRAM"
        live_metrics.ring2_icon = "󰢮"
        live_metrics.ring2_invert = false
        live_metrics.ring2_text = string.format("%.1fG", used / 1073741824)
    else
        -- Fallback for desktop without battery or sysfs VRAM: show Swap
        live_metrics.ring2_label = "SWAP"
        live_metrics.ring2_icon = "󰓡"
        live_metrics.ring2_invert = false
        if swap_total > 0 then
            local swap_used = math.max(0, swap_total - swap_free)
            live_metrics.ring2_perc = math.min(100, math.floor((swap_used * 100) / swap_total + 0.5))
            live_metrics.ring2_text = string.format("%.1fG", swap_used / 1048576)
        else
            live_metrics.ring2_perc = 0
            live_metrics.ring2_text = "0.0G"
        end
    end

    -- 3. Ring 3: GPU Load (AMD gpu_busy_percent, Intel GT frequencies, or fallback)
    local gpu_val = nil
    if hw.drm_card_path and hw.drm_card_path ~= "" then
        gpu_val = read_file_num(hw.drm_card_path .. "/gpu_busy_percent")
    end
    if gpu_val == nil and hw.drm_card_dir and hw.drm_card_dir ~= "" then
        local act_f = read_file_num(hw.drm_card_dir .. "/gt_act_freq_mhz")
            or read_file_num(hw.drm_card_dir .. "/device/tile0/gt0/freq0/act_freq")
        local max_f = read_file_num(hw.drm_card_dir .. "/gt_max_freq_mhz")
            or read_file_num(hw.drm_card_dir .. "/device/tile0/gt0/freq0/max_freq")
        if act_f and max_f and max_f > 0 then
            gpu_val = math.min(100, math.floor((act_f * 100) / max_f + 0.5))
        else
            local cur_f = read_file_num(hw.drm_card_dir .. "/gt_cur_freq_mhz")
            local min_f = read_file_num(hw.drm_card_dir .. "/gt_min_freq_mhz") or 0
            if cur_f and max_f and max_f > min_f then
                gpu_val = math.max(0, math.min(100, math.floor(((cur_f - min_f) * 100) / (max_f - min_f) + 0.5)))
            end
        end
    end
    gpu_val = math.max(0, math.min(100, gpu_val or 0))
    live_metrics.gpu_perc = gpu_val
    live_metrics.gpu_text = string.format("%d%%", gpu_val)

    -- 4. Temperatures (Ring 4 & CPU Card Header)
    local ring_t = read_temp_celsius(hw.gpu_temp_path)
    local cpu_t = read_temp_celsius(hw.cpu_temp_path)
    if ring_t <= 0 then ring_t = cpu_t end

    live_metrics.temp_perc = math.max(0, math.min(100, ring_t))
    live_metrics.temp_text = string.format("%d°C", ring_t)
    live_metrics.cpu_temp_text = string.format("%d°C", cpu_t)

    return live_metrics
end

-- Conky text hooks for Mimosa.conf lines 90-91
function conky_ring_val(idx_str)
    local m = update_live_metrics()
    local idx = tonumber(idx_str) or 1
    if idx == 1 then return m.ram_text
    elseif idx == 2 then return m.ring2_text
    elseif idx == 3 then return m.gpu_text
    elseif idx == 4 then return m.temp_text
    end
    return ""
end

function conky_cpu_header()
    local hw = get_hw_profile()
    return hw.cpu_name or "PROCESSOR"
end

function conky_cpu_temp()
    local m = update_live_metrics()
    return m.cpu_temp_text
end

-- Ring configuration table
system_rings = {
    {
        max = 100,
        x = 49.5, y = 330.0,
        radius = 23,
        thickness = 6.0,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xffffff,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true,
        dynamic_color = true,
        icon = '',
        icon_size = 16,
        label = 'RAM',
        get_state = function(m)
            return m.ram_perc, 'RAM', '', false, m.ram_text
        end,
    },
    {
        max = 100,
        x = 119.7, y = 330.0,
        radius = 23,
        thickness = 6.0,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xffffff,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true,
        dynamic_color = true,
        icon = '󰢮',
        icon_size = 18,
        label = 'VRAM',
        get_state = function(m)
            return m.ring2_perc, m.ring2_label, m.ring2_icon, m.ring2_invert, m.ring2_text
        end,
    },
    {
        max = 100,
        x = 190.0, y = 330.0,
        radius = 23,
        thickness = 6.0,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xFFFFFF,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true,
        dynamic_color = true,
        icon = '󰾲',
        icon_size = 19,
        label = 'GPU',
        get_state = function(m)
            return m.gpu_perc, 'GPU', '󰾲', false, m.gpu_text
        end,
    },
    {
        max = 100,
        x = 259.5, y = 330.0,
        radius = 23,
        thickness = 6.0,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xFFFFFF,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true,
        dynamic_color = true,
        icon = '',
        icon_size = 16,
        label = 'TEMP',
        get_state = function(m)
            return m.temp_perc, 'TEMP', '', false, m.temp_text
        end,
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
function draw_system_ring(cr, ring, value, label_override, icon_override, invert_color, value_text)
    local angle_0 = (ring.start_angle or 0) * math.pi/180 - math.pi/2
    local angle_f = (ring.end_angle or 360) * math.pi/180 - math.pi/2
    local angle_v = angle_0 + (angle_f - angle_0) * (value / ring.max)

    -- Dynamic thermal/load/battery color calculation
    local fg_col = ring.fg_color
    if ring.dynamic_color then
        if invert_color then
            -- Battery semantics: low is red, medium is amber, high is green
            if value <= 20 then
                fg_col = 0xff453a -- Low battery: Coral Red
            elseif value <= 40 then
                fg_col = 0xff9f0a -- Medium battery: Amber Orange
            else
                fg_col = ring.fg_color or 0x32d74c -- Healthy charge: Bright Green
            end
        else
            -- Resource load semantics: high is red, medium is amber, low is green
            if value >= 80 then
                fg_col = 0xff453a -- High load / Temp warning: Coral Red
            elseif value >= 60 then
                fg_col = 0xff9f0a -- Medium load: Amber Orange
            else
                fg_col = ring.fg_color or 0x32d74c -- Normal: Bright Green
            end
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

    local icon_txt = icon_override or ring.icon
    if icon_txt then
        cairo_select_font_face(cr, "Hack Nerd Font", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, ring.icon_size or 18)
        cairo_set_source_rgba(cr, 1, 1, 1, 1)

        local ok, extents = pcall(function() return cairo_text_extents_t:create() end)
        if ok and extents then
            cairo_text_extents(cr, icon_txt, extents)
            local move_x = ring.x - (extents.width / 2 + extents.x_bearing)
            local move_y = ring.y - (extents.height / 2 + extents.y_bearing)
            cairo_move_to(cr, move_x, move_y)
        else
            cairo_move_to(cr, ring.x - (ring.icon_size or 18) / 2, ring.y + (ring.icon_size or 18) / 3)
        end
        cairo_show_text(cr, icon_txt)
    end

    local lbl_txt = label_override or ring.label
    if lbl_txt then
        cairo_select_font_face(cr, "Inter", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(cr, 10.5)
        cairo_set_source_rgba(cr, 0.1960, 0.8431, 0.2980, 1.0)
        local ok, extents = pcall(function() return cairo_text_extents_t:create() end)
        if ok and extents then
            cairo_text_extents(cr, lbl_txt, extents)
            cairo_move_to(cr, ring.x - (extents.width / 2 + extents.x_bearing), ring.y + 42)
        else
            cairo_move_to(cr, ring.x - 12, ring.y + 42)
        end
        cairo_show_text(cr, lbl_txt)
    end

    if value_text and value_text ~= "" then
        cairo_select_font_face(cr, "Bebas Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 21.5)
        cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.95)
        local ok, extents = pcall(function() return cairo_text_extents_t:create() end)
        if ok and extents then
            cairo_text_extents(cr, value_text, extents)
            cairo_move_to(cr, ring.x - (extents.width / 2 + extents.x_bearing), ring.y + 68)
        else
            cairo_move_to(cr, ring.x - 14, ring.y + 68)
        end
        cairo_show_text(cr, value_text)
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

-- Calculates average load for a physical core across all its SMT sibling threads
local last_core_check = 0
local cached_loads = {}

local function get_physical_core_load(core_info, total_cores)
    local now = os.time()
    local cid = core_info.core_num
    if cached_loads[cid] and (now - last_core_check < 1) then
        return cached_loads[cid]
    end
    local sum = 0
    for _, cpu_idx in ipairs(core_info.cpus) do
        local val = tonumber(conky_parse('${cpu cpu' .. (cpu_idx + 1) .. '}')) or 0
        sum = sum + val
    end
    local avg = math.floor(sum / #core_info.cpus + 0.5)
    if avg < 0 then avg = 0 end
    if avg > 100 then avg = 100 end
    cached_loads[cid] = avg
    if cid == total_cores then last_core_check = now end
    return avg
end

-- Renders adaptive physical cores and total CPU load for Card 3
local last_total_cpu_check = 0
local cached_total_cpu = 0

function draw_cpu_card(cr)
    local hw = get_hw_profile()
    local cores, detected_threads = get_physical_cores()
    local num_cores = #cores
    local num_threads = hw.logical_threads or detected_threads or num_cores

    -- 1. Left: Hero Ring for Total CPU Load
    local xc = 56.0
    local yc = 533.0
    local radius = 26.0
    local thickness = 5.5

    local now_cpu = os.time()
    if now_cpu - last_total_cpu_check >= 1 or last_total_cpu_check == 0 then
        cached_total_cpu = tonumber(conky_parse('${cpu}')) or 0
        if cached_total_cpu < 0 then cached_total_cpu = 0 end
        if cached_total_cpu > 100 then cached_total_cpu = 100 end
        last_total_cpu_check = now_cpu
    end
    local total_cpu = cached_total_cpu

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
    cairo_select_font_face(cr, "Bebas Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 19.5)
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

    -- Dynamic micro-label under ring: "<N> CORES · <T> TH"
    cairo_select_font_face(cr, "Abel", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 7.5)
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.6)
    local ok_sub, ext_sub = pcall(function() return cairo_text_extents_t:create() end)
    local sub_txt = string.format("%d CORES · %d TH", num_cores, num_threads)
    if ok_sub and ext_sub then
        cairo_text_extents(cr, sub_txt, ext_sub)
        cairo_move_to(cr, xc - (ext_sub.width / 2 + ext_sub.x_bearing), yc + 53)
    else
        cairo_move_to(cr, xc - 28, yc + 53)
    end
    cairo_show_text(cr, sub_txt)

    -- 2. Right: Adaptive Two-Column Core Matrix
    local rows = math.max(1, math.ceil(num_cores / 2))
    local col1_x = 112
    local col2_x = 202
    local header_y = 482

    local col1_hdr, col2_hdr
    if hw.is_x3d and num_cores == 12 then
        col1_hdr = "CCD0 · V-CACHE"
        col2_hdr = "CCD1 · FREQ"
    else
        col1_hdr = string.format("CORES 01-%02d", rows)
        col2_hdr = string.format("CORES %02d-%02d", math.min(num_cores, rows + 1), num_cores)
    end

    local col1_center = col1_x + 40.0
    local col2_center = col2_x + 40.0

    cairo_select_font_face(cr, "Inter", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 8.5)
    cairo_set_source_rgba(cr, 0.1960, 0.8431, 0.2980, 0.95)

    local ok1, ext1 = pcall(function() return cairo_text_extents_t:create() end)
    if ok1 and ext1 then
        cairo_text_extents(cr, col1_hdr, ext1)
        cairo_move_to(cr, col1_center - (ext1.width / 2 + ext1.x_bearing), header_y)
    else
        cairo_move_to(cr, col1_x, header_y)
    end
    cairo_show_text(cr, col1_hdr)

    if num_cores > 1 then
        local ok2, ext2 = pcall(function() return cairo_text_extents_t:create() end)
        if ok2 and ext2 then
            cairo_text_extents(cr, col2_hdr, ext2)
            cairo_move_to(cr, col2_center - (ext2.width / 2 + ext2.x_bearing), header_y)
        else
            cairo_move_to(cr, col2_x, header_y)
        end
        cairo_show_text(cr, col2_hdr)
    end

    -- Calculate adaptive vertical spacing to fit cleanly in Card 3
    local row_step = 22
    local bar_h = 5.5
    local y_start = 495

    if rows <= 4 then
        row_step = 28
        y_start = 506
        bar_h = 6.0
    elseif rows == 5 then
        row_step = 25
        y_start = 502
        bar_h = 6.0
    elseif rows == 6 then
        row_step = 22
        y_start = 495
        bar_h = 5.5
    else
        y_start = 494
        row_step = math.max(14, math.floor(130 / rows))
        bar_h = 4.5
    end

    local bar_w = 38
    local bar_r = bar_h / 2

    for k = 1, rows do
        local row_y = y_start + (k - 1) * row_step

        -- --- Column 1: Core k ---
        local c1_idx = k
        if cores[c1_idx] then
            local load1 = get_physical_core_load(cores[c1_idx], num_cores)
            local lbl1 = string.format("C%02d", c1_idx)

            cairo_select_font_face(cr, "Inter", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
            cairo_set_font_size(cr, 8.0)
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.75)
            cairo_move_to(cr, col1_x, row_y + 6)
            cairo_show_text(cr, lbl1)

            local bar1_x = col1_x + 22
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.12)
            draw_rounded_rect(cr, bar1_x, row_y, bar_w, bar_h, bar_r)
            cairo_fill(cr)

            if load1 > 0 then
                local fill1_w = math.max(2 * bar_r, (load1 / 100.0) * bar_w)
                if fill1_w > bar_w then fill1_w = bar_w end
                local col1_fg = get_load_color(load1)
                cairo_set_source_rgba(cr, rgb_to_r_g_b(col1_fg, 0.95))
                draw_rounded_rect(cr, bar1_x, row_y, fill1_w, bar_h, bar_r)
                cairo_fill(cr)
            end

            local val1_txt = string.format("%d%%", load1)
            cairo_select_font_face(cr, "Abel", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
            cairo_set_font_size(cr, 8.0)
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.85)
            local ok_v1, ext_v1 = pcall(function() return cairo_text_extents_t:create() end)
            if ok_v1 and ext_v1 then
                cairo_text_extents(cr, val1_txt, ext_v1)
                cairo_move_to(cr, bar1_x + bar_w + 21 - (ext_v1.width + ext_v1.x_bearing), row_y + 6)
            else
                cairo_move_to(cr, bar1_x + bar_w + 5, row_y + 6)
            end
            cairo_show_text(cr, val1_txt)
        end

        -- --- Column 2: Core k + rows ---
        local c2_idx = k + rows
        if cores[c2_idx] then
            local load2 = get_physical_core_load(cores[c2_idx], num_cores)
            local lbl2 = string.format("C%02d", c2_idx)

            cairo_select_font_face(cr, "Inter", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
            cairo_set_font_size(cr, 8.0)
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.75)
            cairo_move_to(cr, col2_x, row_y + 6)
            cairo_show_text(cr, lbl2)

            local bar2_x = col2_x + 22
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.12)
            draw_rounded_rect(cr, bar2_x, row_y, bar_w, bar_h, bar_r)
            cairo_fill(cr)

            if load2 > 0 then
                local fill2_w = math.max(2 * bar_r, (load2 / 100.0) * bar_w)
                if fill2_w > bar_w then fill2_w = bar_w end
                local col2_fg = get_load_color(load2)
                cairo_set_source_rgba(cr, rgb_to_r_g_b(col2_fg, 0.95))
                draw_rounded_rect(cr, bar2_x, row_y, fill2_w, bar_h, bar_r)
                cairo_fill(cr)
            end

            local val2_txt = string.format("%d%%", load2)
            cairo_select_font_face(cr, "Abel", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
            cairo_set_font_size(cr, 8.0)
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.85)
            local ok_v2, ext_v2 = pcall(function() return cairo_text_extents_t:create() end)
            if ok_v2 and ext_v2 then
                cairo_text_extents(cr, val2_txt, ext_v2)
                cairo_move_to(cr, bar2_x + bar_w + 21 - (ext_v2.width + ext_v2.x_bearing), row_y + 6)
            else
                cairo_move_to(cr, bar2_x + bar_w + 5, row_y + 6)
            end
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

    -- 2. Sample live metrics (cached 1Hz) and draw the 4 rings
    local m = update_live_metrics()
    for _, ring in ipairs(system_rings) do
        local val, lbl, icn, inv, val_txt = ring.get_state(m)
        draw_system_ring(cr, ring, val, lbl, icn, inv, val_txt)
    end

    -- 3. Draw adaptive physical cores and CPU load card
    draw_cpu_card(cr)

    cairo_destroy(cr)
    if need_destroy_cs and cs ~= nil then
        cairo_surface_destroy(cs)
    end
end

function conky_system_rings()
    conky_main_draw()
end
