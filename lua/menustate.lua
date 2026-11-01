if not _G.XPTotalHUD then
	dofile(ModPath .. "lua/core.lua")
end

Hooks:PostHook(MenuMainState, "at_enter", "XPTotalHUD_menu_main_at_enter", function()
	XPTotalHUD:set_in_menu(true)
end)

Hooks:PreHook(MenuMainState, "at_exit", "XPTotalHUD_menu_main_at_exit", function()
	XPTotalHUD:set_in_menu(false)
end)
