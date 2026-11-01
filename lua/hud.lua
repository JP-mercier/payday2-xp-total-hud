if not _G.XPTotalHUD then
	dofile(ModPath .. "lua/core.lua")
end

-- Same parent as the vanilla hint, timer and objectives (and VanillaHUD Plus's HUDList).
Hooks:PostHook(HUDManager, "_setup_player_info_hud_pd2", "XPTotalHUD_setup_player_info_hud_pd2", function(self)
	if self:alive(PlayerBase.PLAYER_INFO_HUD_PD2) then
		XPTotalHUD:create_hud_label(self:script(PlayerBase.PLAYER_INFO_HUD_PD2).panel)
	end
end)
