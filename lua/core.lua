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
	round_thousands = false
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

XPTotalHUD._total = nil
XPTotalHUD._gain = 0
XPTotalHUD._gain_t = nil
XPTotalHUD._level_lines_cache = nil
XPTotalHUD._projection_cache = nil
XPTotalHUD._level_points = nil
XPTotalHUD._hud_label = nil
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

-- True while there is a heist label to feed.
function XPTotalHUD:tracking()
	return self.settings.enabled and self._hud_label ~= nil and alive(self._hud_label.panel) and not self:in_crime_spree()
end

-- Called from the mission_xp_award hooks with the difference in total. Gains in quick succession add up.
function XPTotalHUD:add_gain(amount)
	if amount <= 0 then
		return
	end
	self._gain = (self._gain_t and self._gain or 0) + amount
	self._gain_t = self.GAIN_SECONDS
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
end

XPTotalHUD:load_settings()
