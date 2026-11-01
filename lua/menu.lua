if not _G.XPTotalHUD then
	dofile(ModPath .. "lua/core.lua")
end

-- Maps each menu item to its settings key.
local TOGGLE_KEYS = {
	xp_total_hud_enabled = "enabled",
	xp_total_hud_show_gain = "show_gain",
	xp_total_hud_heist_level_xp = "heist_level_xp",
	xp_total_hud_profile_enabled = "profile_enabled",
	xp_total_hud_lobby_enabled = "lobby_enabled",
	xp_total_hud_round_thousands = "round_thousands"
}
local SLIDER_KEYS = {
	xp_total_hud_pos_x = "pos_x",
	xp_total_hud_pos_y = "pos_y",
	xp_total_hud_lobby_pos_x = "lobby_pos_x",
	xp_total_hud_lobby_pos_y = "lobby_pos_y",
	xp_total_hud_font_size = "font_size",
	xp_total_hud_opacity = "opacity"
}
-- Positions keep the exact slider value so a mouse drag can place a label between steps.
local POSITION_KEYS = {
	pos_x = true,
	pos_y = true,
	lobby_pos_x = true,
	lobby_pos_y = true
}

Hooks:Add("LocalizationManagerPostInit", "XPTotalHUDLocalization", function(loc)
	loc:add_localized_strings({
		xp_total_hud_menu_title = "XP Total HUD",
		xp_total_hud_menu_desc = "Small XP labels for heists, the main menu and lobbies. While this menu is open, a sample heist label and the lobby label show where they sit.",
		xp_total_hud_enabled_title = "Heist: show XP total",
		xp_total_hud_enabled_desc = "What the current day pays in XP if it ends now, with the crew alive right now (XP Notifier's \"Total XP\"). Hidden in Crime Spree.",
		xp_total_hud_pos_x_title = "Heist: horizontal position",
		xp_total_hud_pos_x_desc = "0 = against the left edge, 50 = centered, 100 = against the right edge.",
		xp_total_hud_pos_y_title = "Heist: vertical position",
		xp_total_hud_pos_y_desc = "0 = against the top edge, 100 = against the bottom edge. 65 sits above the bottom-right player panel and the carried-bag box over it.",
		xp_total_hud_show_gain_title = "Heist: show last gain",
		xp_total_hud_show_gain_desc = "Shows \"+12,345\" next to the total for 5 seconds after an objective gives XP. Gains in quick succession add up.",
		xp_total_hud_heist_level_xp_title = "Heist: add level XP",
		xp_total_hud_heist_level_xp_desc = "Adds the level lines (total level XP, XP to infamy) under the heist total.",
		xp_total_hud_profile_enabled_title = "Main menu: add to profile box",
		xp_total_hud_profile_enabled_desc = "Adds TOTAL XP (XP earned through your levels since your last infamy) and TO INFAMY (XP left to level 100) under COINS in the profile box. At level 100 while infamous, also the infamy pool.",
		xp_total_hud_lobby_enabled_title = "Lobby: show level XP",
		xp_total_hud_lobby_enabled_desc = "The same lines as a label on the lobby screen, which has no profile box.",
		xp_total_hud_lobby_pos_x_title = "Lobby: horizontal position",
		xp_total_hud_lobby_pos_x_desc = "0 = against the left edge, 50 = centered, 100 = against the right edge.",
		xp_total_hud_lobby_pos_y_title = "Lobby: vertical position",
		xp_total_hud_lobby_pos_y_desc = "0 = against the top edge, 100 = against the bottom edge. 27 sits under the lobby code, above the chat.",
		xp_total_hud_font_size_title = "Text size",
		xp_total_hud_font_size_desc = "Font size of the heist and lobby labels.",
		xp_total_hud_opacity_title = "Opacity (%)",
		xp_total_hud_opacity_desc = "Opacity of the heist and lobby labels.",
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
