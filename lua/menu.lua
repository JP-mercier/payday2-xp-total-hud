if not _G.XPTotalHUD then
	dofile(ModPath .. "lua/core.lua")
end

-- Maps each menu item to its settings key.
local TOGGLE_KEYS = {
	xp_total_hud_enabled = "enabled",
	xp_total_hud_show_gain = "show_gain",
	xp_total_hud_show_level = "show_level",
	xp_total_hud_show_bar = "show_bar",
	xp_total_hud_heist_level_xp = "heist_level_xp",
	xp_total_hud_profile_enabled = "profile_enabled",
	xp_total_hud_lobby_enabled = "lobby_enabled",
	xp_total_hud_round_thousands = "round_thousands",
	xp_total_hud_log_enabled = "log_enabled",
	xp_total_hud_log_show_xp = "log_show_xp",
	xp_total_hud_log_show_objectives = "log_show_objectives",
	xp_total_hud_log_show_done = "log_show_done",
	xp_total_hud_log_show_time = "log_show_time"
}
local SLIDER_KEYS = {
	xp_total_hud_pos_x = "pos_x",
	xp_total_hud_pos_y = "pos_y",
	xp_total_hud_lobby_pos_x = "lobby_pos_x",
	xp_total_hud_lobby_pos_y = "lobby_pos_y",
	xp_total_hud_font_size = "font_size",
	xp_total_hud_opacity = "opacity",
	xp_total_hud_log_pos_x = "log_pos_x",
	xp_total_hud_log_pos_y = "log_pos_y",
	xp_total_hud_log_lines = "log_lines",
	xp_total_hud_log_name_length = "log_name_length",
	xp_total_hud_log_fade = "log_fade"
}
-- Positions keep the exact slider value so a mouse drag can place a label between steps.
local POSITION_KEYS = {
	pos_x = true,
	pos_y = true,
	log_pos_x = true,
	log_pos_y = true,
	lobby_pos_x = true,
	lobby_pos_y = true
}

Hooks:Add("LocalizationManagerPostInit", "XPTotalHUDLocalization", function(loc)
	loc:add_localized_strings({
		xp_total_hud_menu_title = "XP Total HUD",
		xp_total_hud_menu_desc = "Small XP labels for heists, the main menu and lobbies. While this menu is open, a sample heist label, heist log and the lobby label show where they sit.",
		xp_total_hud_enabled_title = "Heist: show XP total",
		xp_total_hud_enabled_desc = "What the current day pays in XP if it ends now, with the crew alive right now (XP Notifier's \"Total XP\"). Hidden in Crime Spree.",
		xp_total_hud_pos_x_title = "Heist: horizontal position",
		xp_total_hud_pos_x_desc = "0 = against the left edge, 50 = centered, 100 = against the right edge.",
		xp_total_hud_pos_y_title = "Heist: vertical position",
		xp_total_hud_pos_y_desc = "0 = against the top edge, 100 = against the bottom edge. 65 sits above the bottom-right player panel and the carried-bag box over it.",
		xp_total_hud_show_gain_title = "Heist: show last gain",
		xp_total_hud_show_gain_desc = "Shows \"+12,345\" next to the total for 5 seconds after an objective gives XP. Gains in quick succession add up.",
		xp_total_hud_show_level_title = "Heist: show level at day end",
		xp_total_hud_show_level_desc = "Adds \"Level 93\" under the total: the level you will be once the day pays out. It turns green and reads \"93 > 94\" when the day will level you up. At level 100 while infamous, shows how full the infamy pool will be.",
		xp_total_hud_show_bar_title = "Heist: show XP bar",
		xp_total_hud_show_bar_desc = "Progress bar for the level you will end the day at. White is the progress you already have, green is what the day adds. At level 100 while infamous, it tracks the infamy pool.",
		xp_total_hud_heist_level_xp_title ="Heist: add level XP",
		xp_total_hud_heist_level_xp_desc = "Adds the level lines (total level XP, XP to infamy) under the heist total.",
		xp_total_hud_log_enabled_title = "Heist log: show",
		xp_total_hud_log_enabled_desc = "A running list of this day's XP awards with what gave each one, with the heist time. Newest line at the bottom.",
		xp_total_hud_log_show_xp_title = "Heist log: XP gains",
		xp_total_hud_log_show_xp_desc = "Shows each XP award with what gave it. XP paid for completing an objective goes on that objective's line (\"+4,000  Open the vault\"); other awards get their own line (\"+6,000  Bag secured\"). Grey = the mission script's name for the award, when nothing else explains it. Not in Crime Spree.",
		xp_total_hud_log_show_objectives_title = "Heist log: new objectives",
		xp_total_hud_log_show_objectives_desc = "Also adds a line for each objective when it appears; XP for completing it then goes on that line instead of its own. Off by default: XP lines already name the objective that paid them.",
		xp_total_hud_log_show_done_title = "Heist log: completed objectives",
		xp_total_hud_log_show_done_desc = "Also adds a \"Done ...\" line when an objective or sub-objective is completed. Off by default: the XP line and the next objective usually say the same.",
		xp_total_hud_log_name_length_title = "Heist log: name length",
		xp_total_hud_log_name_length_desc = "Names drop anything in brackets, then are cut at a word boundary to this many characters, without small words like \"the\" or \"from\" at the end.",
		xp_total_hud_log_show_time_title = "Heist log: heist time",
		xp_total_hud_log_show_time_desc = "Starts each line with the heist timer at that moment, e.g. \"05:37\".",
		xp_total_hud_log_pos_x_title = "Heist log: horizontal position",
		xp_total_hud_log_pos_x_desc = "0 = against the left edge, 50 = centered, 100 = against the right edge.",
		xp_total_hud_log_pos_y_title = "Heist log: vertical position",
		xp_total_hud_log_pos_y_desc = "0 = against the top edge, 100 = against the bottom edge. At 50 or less the lines fill from the top down, above 50 from the bottom up.",
		xp_total_hud_log_lines_title = "Heist log: lines",
		xp_total_hud_log_lines_desc = "How many of the latest lines are shown.",
		xp_total_hud_log_fade_title = "Heist log: fade after (seconds)",
		xp_total_hud_log_fade_desc = "Lines fade out this long after they appear. 0 = they stay until newer lines push them out.",
		xp_total_hud_profile_enabled_title = "Main menu: add to profile box",
		xp_total_hud_profile_enabled_desc = "Adds TOTAL XP (XP earned through your levels since your last infamy) and TO INFAMY (XP left to level 100) under COINS in the profile box. At level 100 while infamous, also the infamy pool.",
		xp_total_hud_lobby_enabled_title = "Lobby: show level XP",
		xp_total_hud_lobby_enabled_desc = "The same lines as a label on the lobby screen, which has no profile box.",
		xp_total_hud_lobby_pos_x_title = "Lobby: horizontal position",
		xp_total_hud_lobby_pos_x_desc = "0 = against the left edge, 50 = centered, 100 = against the right edge.",
		xp_total_hud_lobby_pos_y_title = "Lobby: vertical position",
		xp_total_hud_lobby_pos_y_desc = "0 = against the top edge, 100 = against the bottom edge. 27 sits under the lobby code, above the chat.",
		xp_total_hud_font_size_title = "Text size",
		xp_total_hud_font_size_desc = "Font size of the heist label, heist log and lobby label.",
		xp_total_hud_opacity_title = "Opacity (%)",
		xp_total_hud_opacity_desc = "Opacity of the heist label, heist log and lobby label.",
		xp_total_hud_round_thousands_title = "Round to thousands",
		xp_total_hud_round_thousands_desc = "Shows \"1,235K\" instead of \"1,234,567\"."
	})
end)

Hooks:Add("MenuManagerInitialize", "XPTotalHUDMenu", function(menu_manager)
	MenuCallbackHandler.xp_total_hud_callback_toggle = function(self, item)
		local key = TOGGLE_KEYS[item:name()]
		if key then
			XPTotalHUD.settings[key] = item:value() == "on"
			XPTotalHUD:save_settings()
			XPTotalHUD:apply_settings()
		end
	end

	MenuCallbackHandler.xp_total_hud_callback_slider = function(self, item)
		local key = SLIDER_KEYS[item:name()]
		if key then
			local value = item:value()
			XPTotalHUD.settings[key] = POSITION_KEYS[key] and value or math.round(value)
			XPTotalHUD:save_settings()
			XPTotalHUD:apply_settings()
		end
	end

	-- BLT calls this one with the menu node, not MenuCallbackHandler.
	MenuCallbackHandler.xp_total_hud_focus_changed = function(node, in_focus)
		if in_focus then
			XPTotalHUD:show_preview(node)
		else
			XPTotalHUD:hide_preview()
		end
	end

	MenuHelper:LoadFromJsonFile(XPTotalHUD._path .. "menu.json", XPTotalHUD, XPTotalHUD.settings)
end)
