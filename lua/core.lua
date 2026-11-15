-- XP Total HUD: shared state, settings, XP math, the labels and the options preview.
-- Loaded (once) by every other script in this mod.

if _G.XPTotalHUD then
	return
end

XPTotalHUD = {}
XPTotalHUD._path = ModPath
XPTotalHUD._settings_path = SavePath .. "xp_total_hud.json"

XPTotalHUD.settings = {
	enabled = true,
	pos_x = 100,
	pos_y = 65,
	show_gain = true,
	show_level = true,
	show_bar = true,
	heist_level_xp = false,
	profile_enabled = true,
	lobby_enabled = true,
	lobby_pos_x = 0,
	lobby_pos_y = 27,
	font_size = 18,
	opacity = 100,
	round_thousands = false,
	log_enabled = true,
	log_show_xp = true,
	log_show_objectives = true,
	log_show_done = false,
	log_show_time = true,
	log_name_length = 28,
	log_pos_x = 100,
	log_pos_y = 40,
	log_lines = 6,
	log_fade = 0
}

-- The heist total also moves when players die, go into custody or leave, not only when objectives
-- give XP. Level XP changes in menus when you go infamous.
XPTotalHUD.REFRESH_INTERVAL = 1
-- How long "+12,345" stays next to the total after an objective gives XP.
XPTotalHUD.GAIN_SECONDS = 5
XPTotalHUD.GAP = 6
XPTotalHUD.PREFIX_COLOR = Color(0.7, 0.7, 0.7)
XPTotalHUD.GAIN_COLOR = Color(0.45, 0.9, 0.45)
XPTotalHUD.SHADOW_COLOR = Color.black:with_alpha(0.75)
XPTotalHUD.BAR_GAP = 3
XPTotalHUD.BAR_BG_COLOR = Color.black:with_alpha(0.6)
XPTotalHUD.BAR_CURRENT_COLOR = Color(0.8, 0.8, 0.8)
-- Sample numbers for the options preview of the heist label.
XPTotalHUD.PREVIEW_TOTAL = 1234567
XPTotalHUD.PREVIEW_GAIN = 12345
-- Log: entries kept per heist day (loot awards can add many XP entries), and seconds a line takes to
-- fade out once it's older than the fade setting.
XPTotalHUD.LOG_KEEP = 60
XPTotalHUD.LOG_FADE_OUT = 1
XPTotalHUD.LOG_TEXT_COLOR = Color(0.9, 0.9, 0.9)
-- An XP award is credited to a sub-objective or objective completed this many seconds before or
-- after it. Mission scripts run the XP and objective elements together,
-- in either order.
XPTotalHUD.CAUSE_WINDOW = 2
-- Awards with the same cause this close together are one line.
XPTotalHUD.LOG_MERGE_SECONDS = 1
-- Words dropped from mission element names when one is shown as the cause ("xp_hack_done_002" ->
-- "Hack done").
XPTotalHUD.ELEMENT_NAME_STOP_WORDS = {
	xp = true, exp = true, experience = true, give = true, func = true, award = true, add = true,
	element = true, logic = true, trigger = true, mission = true, points = true, point = true
}
-- Sample lines for the options preview of the log.
XPTotalHUD.PREVIEW_LOG = {
	{ kind = "new", text = "Find the security room", time = "00:42" },
	{ kind = "done", text = "Find the security room", time = "02:10" },
	{ kind = "xp", amount = 4000, time = "02:10", cause = "Find the security room", cause_kind = "done" },
	{ kind = "new", text = "Find dirt on Alice Rainey (Email, Voicemail, Photos)", time = "02:11" },
	{ kind = "sub", text = "Email", time = "03:20" },
	{ kind = "xp", amount = 30870, time = "03:20", cause = "Email", cause_kind = "sub" },
	{ kind = "sub", text = "Voicemail", time = "04:02" },
	{ kind = "xp", amount = 30870, time = "04:02", cause = "Voicemail", cause_kind = "sub" },
	{ kind = "xp", amount = 8000, time = "04:30", cause = "Pager answered", cause_kind = "element" },
	{ kind = "done", text = "Find dirt on Alice Rainey (Email, Voicemail, Photos)", time = "05:37" },
	{ kind = "xp", amount = 339570, time = "05:37", cause = "Find dirt on Alice Rainey (Email, Voicemail, Photos)", cause_kind = "done" },
	{ kind = "new", text = "Escape available", time = "05:38" }
}

XPTotalHUD._total = nil
XPTotalHUD._gain = 0
XPTotalHUD._gain_t = nil
XPTotalHUD._level_lines_cache = nil
XPTotalHUD._projection_cache = nil
XPTotalHUD._level_points = nil
XPTotalHUD._hud_label = nil
XPTotalHUD._log = {}
XPTotalHUD._log_label = nil
XPTotalHUD._log_preview = nil
XPTotalHUD._ws = nil
XPTotalHUD._lobby_label = nil
XPTotalHUD._preview = nil
XPTotalHUD._in_menu = false
XPTotalHUD._preview_visible = false
XPTotalHUD._options_node = nil
XPTotalHUD._error_logged = false

----------------------------------------------------------------
-- Settings
----------------------------------------------------------------
function XPTotalHUD:load_settings()
	local file = io.open(self._settings_path, "r")
	if not file then
		return
	end
	local ok, data = pcall(json.decode, file:read("*all"))
	file:close()
	if ok and type(data) == "table" then
		for k, v in pairs(data) do
			if self.settings[k] ~= nil then
				self.settings[k] = v
			end
		end
	end
end

function XPTotalHUD:save_settings()
	local file = io.open(self._settings_path, "w+")
	if file then
		file:write(json.encode(self.settings))
		file:close()
	end
end

-- Called after any option changes. The profile box picks up changes the next time it is built,
-- which happens every time the main menu screen is shown again.
function XPTotalHUD:apply_settings()
	self:update_preview()
	self:refresh()
end

----------------------------------------------------------------
-- XP
----------------------------------------------------------------
-- Labels refresh every second, so a failure keeps the last text instead of crashing the game.
function XPTotalHUD:_safe(func)
	local ok, result = pcall(func, self)
	if ok then
		return result
	end
	if not self._error_logged then
		self._error_logged = true
		log("[XP Total HUD] " .. tostring(result))
	end
	return nil
end

-- Same number as XP Notifier's "Total XP": what the current day pays if it ends now, with the crew
-- that is alive and our custody state. MissionEndState passes the same arguments on a success.
function XPTotalHUD:_compute_total()
	local session = managers.network and managers.network:session()
	if not session or not managers.experience or not managers.job or not managers.job:has_active_job() then
		return nil
	end
	local total = managers.experience:get_xp_dissected(true, session:amount_of_alive_players(), not Utils:IsInCustody())
	return total
end

function XPTotalHUD:current_total()
	return self:_safe(self._compute_total)
end

-- Points for levels 1 to the cap. tweak_data also holds unused entries past it (146-193).
function XPTotalHUD:_get_level_points()
	if not self._level_points then
		local points = {}
		for i = 1, managers.experience:level_cap() do
			points[i] = tweak_data:get_value("experience_manager", "levels", i, "points") or 0
		end
		self._level_points = points
	end
	return self._level_points
end

-- XP earned through the levels of the current infamy rank and XP left to level 100. Once infamous at
-- level 100, XP goes to the infamy pool instead (prestige XP, which _increase_infamous_with_prestige
-- spends instead of resetting the level), so that line replaces the level ones.
function XPTotalHUD:_compute_level_lines()
	local xp = managers.experience
	local level, cap = xp:current_level(), xp:level_cap()
	local max_rank = xp:current_rank() >= tweak_data.infamy.ranks
	local earned, needed = 0, 0
	for i, points in ipairs(self:_get_level_points()) do
		needed = needed + points
		if i <= level then
			earned = earned + points
		end
	end

	if level < cap then
		earned = earned + xp:next_level_data_current_points()
		return {
			{ "Total XP", self:format_xp(earned) },
			{ max_rank and "To level 100" or "To infamy", self:format_xp(needed - earned) }
		}
	end

	local lines = { { "Total XP", self:format_xp(needed) } }
	if not max_rank then
		table.insert(lines, { "To infamy", "ready" })
	end
	if xp:current_rank() > 0 then
		table.insert(lines, { "Infamy pool", self:format_xp(xp:get_current_prestige_xp()) .. " / " .. self:format_xp(xp:get_max_prestige_xp()) })
	end
	return lines
end

-- Where the day leaves you if it pays `total`, following ExperienceManager:add_points: each level takes
-- what is left of its points, and at the level cap the rest goes to the infamy pool when infamous (lost
-- otherwise). `start` and `fill` are the bar's white and green ends, as fractions of the end level (or
-- of the pool). After a level-up the white part is empty: progress in the new level is all from the day.
function XPTotalHUD:_compute_projection(total)
	local xp = managers.experience
	local level, cap = xp:current_level(), xp:level_cap()
	if level >= cap then
		if xp:current_rank() == 0 then
			return { level = level, end_level = level, start = 1, fill = 1 }
		end
		local pool, max = xp:get_current_prestige_xp(), xp:get_max_prestige_xp()
		if max <= 0 then
			return nil
		end
		return { level = level, end_level = level, pool = true, start = pool / max, fill = math.min(pool + total, max) / max }
	end

	local points = self:_get_level_points()
	local end_level = level
	local current, needed = xp:next_level_data_current_points(), xp:next_level_data_points()
	local start, left = current, total
	while needed > 0 and left >= needed - current do
		left = left - (needed - current)
		end_level = end_level + 1
		current, start = 0, 0
		if end_level >= cap then
			return { level = level, end_level = end_level, start = 0, fill = 1 }
		end
		needed = points[end_level + 1] or 0
	end
	if needed <= 0 then
		return nil
	end
	return { level = level, end_level = end_level, start = start / needed, fill = (current + left) / needed }
end

-- The level line: "Level 93", or "Level 93 > 94" in green when the day levels you up. At level 100 while
-- infamous, the infamy pool's fill after the day instead.
function XPTotalHUD:_projection_line(projection)
	if projection.pool then
		return { "Infamy pool", math.floor(projection.fill * 100) .. "%" }
	end
	if projection.end_level > projection.level then
		return { "Level", projection.level .. " > " .. projection.end_level, self.GAIN_COLOR }
	end
	return { "Level", tostring(projection.level) }
end

-- Appends the level lines (last good ones if the calculation fails) to `lines`.
function XPTotalHUD:_append_level_lines(lines)
	self._level_lines_cache = self:_safe(self._compute_level_lines) or self._level_lines_cache
	for _, line in ipairs(self._level_lines_cache or {}) do
		table.insert(lines, line)
	end
	return lines
end

-- Crime Spree pays XP by spree level, so the heist formula would show a wrong number.
function XPTotalHUD:in_crime_spree()
	return managers.crime_spree and managers.crime_spree:is_active() or false
end

-- True while in a heist that pays XP the normal way. Gains are recorded even while the label or the
-- log is turned off, so turning the log on mid-heist shows what already happened.
function XPTotalHUD:tracking()
	return self._hud_label ~= nil and alive(self._hud_label.panel) and not self:in_crime_spree()
end

-- Called from the mission_xp_award hooks with the difference in total, and the editor name and base
-- amount of the Experience element giving it. Gains in quick succession add up.
function XPTotalHUD:add_gain(amount, element_name, base_amount)
	if amount <= 0 then
		return
	end
	self._gain = (self._gain_t and self._gain or 0) + amount
	self._gain_t = self.GAIN_SECONDS
	self:_safe(function()
		self:log_xp(amount, element_name, base_amount)
	end)
	self:refresh()
end

function XPTotalHUD:format_xp(n)
	if self.settings.round_thousands and n >= 1000 then
		return managers.experience:experience_string(math.floor((n + 500) / 1000)) .. "K"
	end
	return managers.experience:experience_string(n)
end

----------------------------------------------------------------
-- Labels
----------------------------------------------------------------
-- One piece of text with a drop shadow behind it.
function XPTotalHUD:_create_piece(parent, name, color)
	local piece = parent:panel({ name = name })
	for _, data in ipairs({
		{ name = "shadow", color = self.SHADOW_COLOR, x = 1, y = 1, layer = 0 },
		{ name = "text", color = color, x = 0, y = 0, layer = 1 }
	}) do
		piece:text({
			name = data.name,
			text = "",
			font = tweak_data.hud.medium_font_noshadow,
			font_size = self.settings.font_size,
			color = data.color,
			x = data.x,
			y = data.y,
			layer = data.layer,
			align = "left",
			vertical = "top",
			wrap = false,
			word_wrap = false
		})
	end
	return piece
end

function XPTotalHUD:_set_piece_text(piece, str)
	local text = piece:child("text")
	local shadow = piece:child("shadow")
	local max_w = piece:parent():w()
	for _, t in ipairs({ text, shadow }) do
		t:set_font_size(self.settings.font_size)
		t:set_w(max_w)
		t:set_text(str)
	end
	local _, _, w, h = text:text_rect()
	w, h = math.ceil(w), math.ceil(h)
	text:set_size(w, h)
	shadow:set_size(w, h)
	piece:set_size(w + 1, h + 1)
end

-- Background, then white (progress before the day) and green (what the day adds) fills.
function XPTotalHUD:_create_bar(parent)
	local bar = parent:panel({ name = "bar" })
	bar:rect({ name = "bg", color = self.BAR_BG_COLOR, layer = 0 })
	bar:rect({ name = "current", color = self.BAR_CURRENT_COLOR, layer = 1 })
	bar:rect({ name = "gain", color = self.GAIN_COLOR, layer = 2 })
	return bar
end

function XPTotalHUD:_set_bar(bar, w, h, start, fill)
	local start_w = math.round(w * math.clamp(start, 0, 1))
	local fill_w = math.max(math.round(w * math.clamp(fill, 0, 1)), start_w)
	bar:set_size(w, h)
	bar:child("bg"):set_size(w, h)
	bar:child("current"):set_size(start_w, h)
	bar:child("gain"):set_shape(start_w, 0, fill_w - start_w, h)
end

-- Stacked "Prefix value" lines, plus a "+12,345" beside the first line.
function XPTotalHUD:_create_label(parent, name, layer)
	local panel = parent:panel({
		name = name,
		layer = layer or 0,
		halign = "grow",
		valign = "grow"
	})
	return {
		panel = panel,
		lines = {},
		gain = self:_create_piece(panel, "gain", self.GAIN_COLOR),
		bar = self:_create_bar(panel)
	}
end

-- Positions are percentages of the HUD area: 0 puts the block against the left/top edge and 100
-- against the right/bottom edge, so it never leaves the screen. Lines align to the edge the block is
-- near, and the gain goes on the inner side of the first line so that line doesn't shift. A line's
-- optional third entry colors its value. `bar` ({ start, fill }) adds a progress bar under the lines.
function XPTotalHUD:_set_label(label, lines, gain, pos_x, pos_y, bar)
	for i, line in ipairs(lines) do
		local piece = label.lines[i]
		if not piece then
			piece = self:_create_piece(label.panel, "line" .. i, Color.white)
			label.lines[i] = piece
		end
		piece:set_visible(true)
		self:_set_piece_text(piece, line[1] .. " " .. line[2])
		piece:child("text"):set_range_color(0, #line[1], self.PREFIX_COLOR)
		if line[3] then
			piece:child("text"):set_range_color(#line[1] + 1, #line[1] + 1 + #line[2], line[3])
		end
	end
	for i = #lines + 1, #label.lines do
		label.lines[i]:set_visible(false)
	end

	local panel = label.panel
	local block_w, block_h = 0, 0
	for i = 1, #lines do
		block_w = math.max(block_w, label.lines[i]:w())
		block_h = block_h + label.lines[i]:h()
	end
	-- Minimum width so the bar doesn't jump as the numbers above it change length.
	local bar_w, bar_h = math.max(block_w, self.settings.font_size * 8), math.max(3, math.round(self.settings.font_size / 3))
	if bar then
		block_w = bar_w
		block_h = block_h + self.BAR_GAP + bar_h
	end
	local px, py = pos_x / 100, pos_y / 100
	local x = math.round(px * (panel:w() - block_w))
	local y = math.round(py * (panel:h() - block_h))
	local function place(piece)
		if px > 0.5 then
			piece:set_x(x + block_w - piece:w())
		elseif px < 0.5 then
			piece:set_x(x)
		else
			piece:set_x(math.round(x + (block_w - piece:w()) / 2))
		end
		piece:set_y(y)
		y = y + piece:h()
	end
	for i = 1, #lines do
		place(label.lines[i])
	end
	label.bar:set_visible(bar ~= nil)
	if bar then
		self:_set_bar(label.bar, bar_w, bar_h, bar.start, bar.fill)
		y = y + self.BAR_GAP
		place(label.bar)
	end

	local show_gain = gain ~= nil and gain > 0 and #lines > 0
	label.gain:set_visible(show_gain)
	if show_gain then
		local first = label.lines[1]
		self:_set_piece_text(label.gain, "+" .. self:format_xp(gain))
		if px > 0.5 then
			label.gain:set_right(first:x() - self.GAP)
		else
			label.gain:set_x(first:right() + self.GAP)
		end
		label.gain:set_y(first:y())
	end
	panel:set_alpha(self.settings.opacity / 100)
end

-- Heist label lines: the day's total, the level lines if enabled, then the level the day ends at.
-- Also returns the projection for the bar, or nil when the bar is off.
function XPTotalHUD:_heist_lines(total)
	local lines = { { "XP", self:format_xp(total) } }
	if self.settings.heist_level_xp then
		self:_append_level_lines(lines)
	end
	if not self.settings.show_level and not self.settings.show_bar then
		return lines
	end
	self._projection_cache = self:_safe(function()
		return self:_compute_projection(total)
	end) or self._projection_cache
	local projection = self._projection_cache
	if not projection then
		return lines
	end
	if self.settings.show_level then
		table.insert(lines, self:_projection_line(projection))
	end
	return lines, self.settings.show_bar and projection or nil
end

function XPTotalHUD:refresh()
	self:_refresh_hud()
	self:_refresh_log()
	self:_refresh_lobby()
end

----------------------------------------------------------------
-- Heist label
----------------------------------------------------------------
function XPTotalHUD:create_hud_label(hud_panel)
	local old = hud_panel:child("xp_total_hud")
	if old then
		hud_panel:remove(old)
	end
	self._total = nil
	self._gain = 0
	self._gain_t = nil
	self._hud_label = self:_create_label(hud_panel, "xp_total_hud")
	self._hud_label.panel:animate(function()
		self:_hud_update()
	end)
	self:_refresh_hud()
	self:create_log_label(hud_panel)
end

function XPTotalHUD:_hud_update()
	local refresh_t = 0
	while true do
		local dt = coroutine.yield()
		refresh_t = refresh_t - dt
		if self._gain_t then
			self._gain_t = self._gain_t - dt
			if self._gain_t <= 0 then
				self._gain_t = nil
				self._gain = 0
				refresh_t = 0
			end
		end
		if refresh_t <= 0 then
			refresh_t = self.REFRESH_INTERVAL
			self:_refresh_hud()
		end
	end
end

function XPTotalHUD:_refresh_hud()
	local label = self._hud_label
	if not label or not alive(label.panel) then
		return
	end
	local show = self.settings.enabled and not self._preview_visible and not self:in_crime_spree()
	if show then
		self._total = self:current_total() or self._total
		show = self._total ~= nil
	end
	label.panel:set_visible(show)
	if show then
		local gain = self.settings.show_gain and self._gain_t and self._gain or nil
		local lines, bar = self:_heist_lines(self._total)
		self:_set_label(label, lines, gain, self.settings.pos_x, self.settings.pos_y, bar)
	end
end

----------------------------------------------------------------
-- Heist log: XP gains and objectives, newest line at the bottom
----------------------------------------------------------------
-- "05:37" from the heist timer, or nil before it starts. Pre-planned heists count down, hence abs.
function XPTotalHUD:_heist_time()
	local central = managers.game_play_central
	local timer = central and central._heist_timer
	if not timer or not timer.running then
		return nil
	end
	local t = math.floor(math.abs(central:get_heist_timer()))
	local h, m, s = math.floor(t / 3600), math.floor(t / 60) % 60, t % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

function XPTotalHUD:_log_add(entry)
	entry.age = 0
	entry.time = self:_safe(self._heist_time)
	table.insert(self._log, entry)
	while #self._log > self.LOG_KEEP do
		table.remove(self._log, 1)
	end
	self:_refresh_log()
end

-- "xp_hack_done_002" -> "Hack done", or nil when nothing meaningful is left.
function XPTotalHUD:_element_label(name)
	if type(name) ~= "string" then
		return nil
	end
	local words = {}
	for word in name:lower():gsub("[_%-%.]", " "):gmatch("%S+") do
		if not word:match("^%d+$") and not self.ELEMENT_NAME_STOP_WORDS[word] then
			table.insert(words, word)
		end
	end
	if #words == 0 then
		return nil
	end
	local label = table.concat(words, " ")
	return label:sub(1, 1):upper() .. label:sub(2)
end

-- Objective names by base XP (lua/ehi_xp_names.lua, built from Extra Heist Info's tables by
-- tools/extract_ehi_xp.py): { levels = { level id -> base XP -> names }, redirect = { level id -> level
-- id } }. False if it can't be loaded.
function XPTotalHUD:_ehi_table()
	if self._ehi == nil then
		local ok, data = pcall(dofile, self._path .. "lua/ehi_xp_names.lua")
		if ok and type(data) == "table" and type(data.levels) == "table" then
			self._ehi = data
		else
			self._ehi = false
			log("[XP Total HUD] couldn't load ehi_xp_names.lua: " .. tostring(data))
		end
	end
	return self._ehi
end

-- The names for a base XP amount on the current level, or nil.
function XPTotalHUD:_ehi_names(base_amount)
	local data = base_amount and self:_ehi_table()
	local level_id = data and Global.game_settings and Global.game_settings.level_id
	if not level_id then
		return nil
	end
	local level = data.levels[data.redirect and data.redirect[level_id] or level_id]
	return level and level[base_amount] or nil
end

-- Causes, best first: EHI's name when the amount has only one on this level, a sub-objective or
-- objective completed within CAUSE_WINDOW seconds, EHI's names when several share the amount, the
-- element name. An objective appearing isn't a cause: XP next to it pays for the step just finished.
local CAUSE_RANK = { ehi = 3, sub = 2, done = 1, ehi_multi = 0.5, element = 0 }

-- Called from the mission_xp_award hooks with the Experience element's editor name and base amount.
-- An objective event that comes right after can still claim the award (log_objective).
function XPTotalHUD:log_xp(amount, element_name, base_amount)
	local now = Application:time()
	local entry = { kind = "xp", amount = amount, t = now }
	local names = self:_ehi_names(base_amount)
	if names and #names == 1 then
		entry.cause, entry.cause_kind = names[1], "ehi"
		self:_log_add(entry)
		return
	end
	for i = #self._log, 1, -1 do
		local event = self._log[i]
		if event.t and now - event.t > self.CAUSE_WINDOW then
			break
		end
		local rank = CAUSE_RANK[event.kind]
		if event.kind ~= "xp" and rank and rank > (CAUSE_RANK[entry.cause_kind] or -1) then
			entry.cause, entry.cause_kind = event.text, event.kind
		end
	end
	if not entry.cause and names and #names > 1 then
		entry.cause, entry.cause_kind = table.concat(names, " / "), "ehi_multi"
	end
	if not entry.cause then
		entry.cause = self:_element_label(element_name)
		entry.cause_kind = entry.cause and "element" or nil
	end
	self:_log_add(entry)
end

-- kind is "new", "done" or "sub" (a sub-objective done). Only recorded during a heist (the log is reset
-- when the HUD is built).
function XPTotalHUD:log_objective(kind, text)
	if not self._log_label or not alive(self._log_label.panel) or type(text) ~= "string" then
		return
	end
	text = self:_trim(text)
	if text == "" then
		return
	end
	-- Some missions activate the same objective twice in a row.
	local last = self._log[#self._log]
	if last and last.kind == kind and last.text == text and last.age < 2 then
		return
	end
	-- XP awarded just before this event, in the same mission script run, belongs to it.
	local now = Application:time()
	local rank = CAUSE_RANK[kind]
	for i = #self._log, 1, -1 do
		local entry = self._log[i]
		if not rank or entry.t and now - entry.t > self.CAUSE_WINDOW then
			break
		end
		if entry.kind == "xp" and rank > (CAUSE_RANK[entry.cause_kind] or -1) then
			entry.cause, entry.cause_kind = text, kind
		end
	end
	self:_log_add({ kind = kind, text = text, t = now })
end

function XPTotalHUD:_trim(text)
	return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- The mission objective text, shortened for the log: anything in brackets goes ("Find dirt on Alice
-- Rainey (Email, Voicemail, ...)" -> "Find dirt on Alice Rainey"), then it's cut at a word boundary to
-- log_name_length characters.
function XPTotalHUD:_short_name(text)
	local short = self:_trim(text:gsub("%b()", ""):gsub("%b[]", ""))
	short = self:_trim(short:gsub("[%s:,;%-]+$", ""))
	if short == "" then
		short = text
	end
	local max = self.settings.log_name_length
	if utf8.len(short) <= max then
		return short
	end
	local cut = utf8.sub(short, 1, max)
	local space = cut:match(".*() ")
	if space and space > #cut / 2 then
		cut = cut:sub(1, space - 1)
	end
	return self:_trim(cut:gsub("[%s:,;%-]+$", "")) .. "..."
end

-- Colored pieces of one log line: { text, color } pairs.
function XPTotalHUD:_log_segments(item)
	local segments = {}
	if self.settings.log_show_time and item.time then
		table.insert(segments, { item.time .. "  ", self.PREFIX_COLOR })
	end
	if item.kind == "xp" then
		if item.cause then
			-- Element names are a best guess from the mission script, so they're grey.
			table.insert(segments, { "+" .. self:format_xp(item.amount) .. "  ", self.GAIN_COLOR })
			local name = item.cause_kind == "element" and item.cause or self:_short_name(item.cause)
			table.insert(segments, { name, item.cause_kind == "element" and self.PREFIX_COLOR or self.LOG_TEXT_COLOR })
		else
			table.insert(segments, { "+" .. self:format_xp(item.amount) .. " XP", self.GAIN_COLOR })
		end
	elseif item.kind == "done" or item.kind == "sub" then
		table.insert(segments, { "Done ", self.GAIN_COLOR })
		table.insert(segments, { self:_short_name(item.text), self.PREFIX_COLOR })
	else
		table.insert(segments, { self:_short_name(item.text), self.LOG_TEXT_COLOR })
	end
	return segments
end

function XPTotalHUD:_log_entry_shown(entry)
	if entry.kind == "xp" then
		return self.settings.log_show_xp
	elseif entry.kind == "done" or entry.kind == "sub" then
		return self.settings.log_show_done
	end
	return self.settings.log_show_objectives
end

-- The last log_lines lines from the entries that pass the filters, oldest first, with their fade
-- alpha. Back-to-back XP entries with the same cause within LOG_MERGE_SECONDS become one line.
-- `fade` overrides the fade setting (0 = no fading).
function XPTotalHUD:_log_view(entries, fade)
	local items = {}
	fade = fade or self.settings.log_fade
	for i = #entries, 1, -1 do
		local entry = entries[i]
		if self:_log_entry_shown(entry) then
			local alpha = 1
			if fade > 0 then
				alpha = math.clamp((fade + self.LOG_FADE_OUT - (entry.age or 0)) / self.LOG_FADE_OUT, 0, 1)
			end
			if alpha <= 0 then
				break
			end
			local newer = items[1]
			if entry.kind == "xp" and newer and newer.kind == "xp" and newer.cause == entry.cause and entry.t and newer.t
				and newer.t - entry.t <= self.LOG_MERGE_SECONDS then
				newer.amount = newer.amount + entry.amount
				newer.time, newer.t = entry.time, entry.t
			elseif #items >= self.settings.log_lines then
				break
			else
				table.insert(items, 1, {
					kind = entry.kind,
					text = entry.text,
					amount = entry.amount,
					cause = entry.cause,
					cause_kind = entry.cause_kind,
					time = entry.time,
					t = entry.t,
					alpha = alpha
				})
			end
		end
	end
	local view = {}
	for i, item in ipairs(items) do
		view[i] = { segments = self:_log_segments(item), alpha = item.alpha }
	end
	return view
end

function XPTotalHUD:_create_log(parent, name, layer)
	return {
		panel = parent:panel({
			name = name,
			layer = layer or 0,
			halign = "grow",
			valign = "grow"
		}),
		lines = {}
	}
end

-- The log keeps room for log_lines lines at its position so lines don't jump around as it fills. Near
-- the top edge (Y 50 or less) it fills from the top of that room, otherwise from the bottom.
function XPTotalHUD:_set_log(log, view, pos_x, pos_y)
	local panel = log.panel
	for i, line in ipairs(view) do
		local piece = log.lines[i]
		if not piece then
			piece = self:_create_piece(panel, "line" .. i, Color.white)
			log.lines[i] = piece
		end
		local str = ""
		for _, segment in ipairs(line.segments) do
			str = str .. segment[1]
		end
		piece:set_visible(true)
		self:_set_piece_text(piece, str)
		local text = piece:child("text")
		local pos = 0
		for _, segment in ipairs(line.segments) do
			local len = utf8.len(segment[1])
			text:set_range_color(pos, pos + len, segment[2])
			pos = pos + len
		end
		piece:set_alpha(line.alpha)
	end
	for i = #view + 1, #log.lines do
		log.lines[i]:set_visible(false)
	end
	panel:set_visible(#view > 0)
	if #view == 0 then
		return
	end

	local line_h = log.lines[1]:h()
	local block_w = 0
	for i = 1, #view do
		block_w = math.max(block_w, log.lines[i]:w())
	end
	local room_h = math.max(self.settings.log_lines, #view) * line_h
	local px, py = pos_x / 100, pos_y / 100
	local x = math.round(px * (panel:w() - block_w))
	local y = math.round(py * (panel:h() - room_h))
	if py > 0.5 then
		y = y + room_h - #view * line_h
	end
	for i = 1, #view do
		local piece = log.lines[i]
		if px > 0.5 then
			piece:set_x(x + block_w - piece:w())
		elseif px < 0.5 then
			piece:set_x(x)
		else
			piece:set_x(math.round(x + (block_w - piece:w()) / 2))
		end
		piece:set_y(y + (i - 1) * line_h)
	end
	panel:set_alpha(self.settings.opacity / 100)
end

function XPTotalHUD:create_log_label(hud_panel)
	local old = hud_panel:child("xp_total_hud_log")
	if old then
		hud_panel:remove(old)
	end
	self._log = {}
	-- Loads the names now (the loading screen) rather than at the first award, mid-heist.
	self:_safe(self._ehi_table)
	self._log_label = self:_create_log(hud_panel, "xp_total_hud_log")
	self._log_label.panel:animate(function()
		self:_log_update()
	end)
	self:_refresh_log()
end

-- Ages the entries; redraws only while a line is fading out.
function XPTotalHUD:_log_update()
	while true do
		local dt = coroutine.yield()
		local fade = self.settings.log_fade
		local redraw = false
		for _, entry in ipairs(self._log) do
			local before = entry.age
			entry.age = before + dt
			if fade > 0 and entry.age > fade and before <= fade + self.LOG_FADE_OUT then
				redraw = true
			end
		end
		if redraw then
			self:_refresh_log()
		end
	end
end

function XPTotalHUD:_refresh_log()
	local log = self._log_label
	if not log or not alive(log.panel) then
		return
	end
	local show = self.settings.log_enabled and not self._preview_visible
	self:_safe(function()
		self:_set_log(log, show and self:_log_view(self._log) or {}, self.settings.log_pos_x, self.settings.log_pos_y)
	end)
end

----------------------------------------------------------------
-- Main menu profile box
----------------------------------------------------------------
-- The level lines go under the profile box's CASH / OFFSHORE ACCOUNT / COINS lines, in their style.
-- The box keeps its bottom edge and grows upward. BLT's notification box is created after it and
-- anchored to its top, so it moves up too.
function XPTotalHUD:add_profile_lines(profile)
	local panel = profile._panel
	local ring = profile._prestige_lp_circle
	if not self.settings.profile_enabled or not panel or not alive(panel) or not ring or not alive(ring) then
		return
	end
	-- PlayerProfileGuiObject:init puts the text column 15 right of the prestige ring (the XP rings
	-- are moved 5 left afterwards, the prestige ring isn't). If nothing sits there, the box isn't the
	-- vanilla one and is left alone.
	local column_x = ring:right() + 15
	local bottom
	for _, child in ipairs(panel:children()) do
		if math.abs(child:x() - column_x) < 1 then
			bottom = math.max(bottom or 0, child:bottom())
		end
	end
	if not bottom then
		return
	end

	local right = 0
	for i, line in ipairs(self:_append_level_lines({})) do
		local text = panel:text({
			name = "xp_total_hud_line" .. i,
			text = "##" .. utf8.to_upper(line[1]) .. "##: " .. utf8.to_upper(line[2]),
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = tweak_data.screen_colors.text
		})
		-- Same label color as the vanilla lines.
		managers.menu_component:make_color_text(text, Color(180, 255, 255, 255) / 255)
		local _, _, w, h = text:text_rect()
		text:set_shape(math.round(column_x), math.round(bottom), math.ceil(w), math.ceil(h))
		bottom = text:bottom()
		right = math.max(right, text:right())
	end

	local panel_bottom = panel:bottom()
	panel:set_size(math.max(panel:w(), right + 10), math.max(panel:h(), bottom + 8))
	panel:set_bottom(panel_bottom)
end

----------------------------------------------------------------
-- Lobby label and options preview
----------------------------------------------------------------
-- Both live on one overlay workspace above menu components and below dialogs. VanillaHUD Plus lays the
-- heist HUD out on its own scaled workspace; the overlay copies that so the preview lines up.
function XPTotalHUD:_overlay_panel()
	if not self._ws then
		self._ws = managers.gui_data:create_saferect_workspace()
		if managers.gui_data.layout_scaled_fullscreen_workspace then
			managers.gui_data:layout_scaled_fullscreen_workspace(self._ws)
		end
	end
	return self._ws:panel()
end

-- MenuMainState covers the main menu, Crime.net and lobbies, but not the title screen.
function XPTotalHUD:set_in_menu(in_menu)
	self._in_menu = in_menu
	if in_menu then
		self:_ensure_lobby_label()
	end
	self:_refresh_lobby()
end

function XPTotalHUD:_on_lobby_screen()
	local menu = managers.menu and managers.menu:active_menu()
	local node = menu and menu.logic and menu.logic:selected_node()
	return node ~= nil and node:parameters().name == "lobby"
end

-- The lobby screen has no profile box, so it gets a floating label, only on that screen (not on the
-- inventory or other screens opened from it). It also shows while the options are open, in menus and
-- in heists, so its position can be set from anywhere.
function XPTotalHUD:_lobby_label_wanted()
	return self.settings.lobby_enabled and (self._preview_visible or self._in_menu and self:_on_lobby_screen()) or false
end

function XPTotalHUD:_ensure_lobby_label()
	if not self._lobby_label and managers.gui_data then
		self._lobby_label = self:_create_label(self:_overlay_panel(), "xp_total_hud_lobby", tweak_data.gui.ATTRACT_SCREEN_LAYER)
		self._lobby_label.panel:animate(function()
			self:_lobby_update()
		end)
	end
	return self._lobby_label
end

-- Follows screen changes every frame; the lines are recomputed every REFRESH_INTERVAL while shown.
function XPTotalHUD:_lobby_update()
	local shown = false
	local refresh_t = 0
	while true do
		local dt = coroutine.yield()
		refresh_t = refresh_t - dt
		local wanted = self:_lobby_label_wanted()
		if wanted ~= shown or wanted and refresh_t <= 0 then
			shown = wanted
			refresh_t = self.REFRESH_INTERVAL
			self:_refresh_lobby()
		end
	end
end

function XPTotalHUD:_refresh_lobby()
	local label = self._lobby_label
	if not label or not alive(label.panel) then
		return
	end
	local lines = self:_lobby_label_wanted() and self:_append_level_lines({}) or {}
	label.panel:set_visible(#lines > 0)
	if #lines > 0 then
		self:_set_label(label, lines, nil, self.settings.lobby_pos_x, self.settings.lobby_pos_y)
	end
end

-- While the options menu is open, a sample heist label shows where the real one sits in heists.
-- In a heist the real label is hidden meanwhile so the two don't overlap.
function XPTotalHUD:show_preview(node)
	if not managers.gui_data then
		return
	end
	self._options_node = node
	if not self._preview then
		self._preview = self:_create_label(self:_overlay_panel(), "xp_total_hud_preview", tweak_data.gui.ATTRACT_SCREEN_LAYER)
	end
	if not self._log_preview then
		self._log_preview = self:_create_log(self:_overlay_panel(), "xp_total_hud_log_preview", tweak_data.gui.ATTRACT_SCREEN_LAYER)
	end
	self:_ensure_lobby_label()
	self._preview_visible = true
	self:update_preview()
	self._preview.panel:stop()
	self._preview.panel:animate(function()
		-- Closing the whole menu (Escape in a heist) skips the node's focus callback.
		repeat
			coroutine.yield()
		until not self._preview_visible or not self:_options_open()
		self:hide_preview()
	end)
	self:refresh()
end

-- Can run inside the preview's own animation, so it only hides the panel.
function XPTotalHUD:hide_preview()
	if not self._preview_visible then
		return
	end
	self._preview_visible = false
	self._options_node = nil
	if self._preview then
		self._preview.panel:set_visible(false)
	end
	if self._log_preview then
		self._log_preview.panel:set_visible(false)
	end
	self:refresh()
end

function XPTotalHUD:_options_open()
	local menu = managers.menu and managers.menu:active_menu()
	return menu ~= nil and menu.logic ~= nil and menu.logic:selected_node() == self._options_node
end

function XPTotalHUD:update_preview()
	if not self._preview_visible or not self._preview then
		return
	end
	self._preview.panel:set_visible(self.settings.enabled)
	if self.settings.enabled then
		local gain = self.settings.show_gain and self.PREVIEW_GAIN or nil
		local lines, bar = self:_heist_lines(self.PREVIEW_TOTAL)
		self:_set_label(self._preview, lines, gain, self.settings.pos_x, self.settings.pos_y, bar)
	end
	-- Sample lines don't fade, so the log stays visible while it's being placed.
	if self._log_preview then
		local view = self.settings.log_enabled and self:_log_view(self.PREVIEW_LOG, 0) or {}
		self:_set_log(self._log_preview, view, self.settings.log_pos_x, self.settings.log_pos_y)
	end
end

XPTotalHUD:load_settings()
