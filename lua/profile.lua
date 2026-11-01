if not _G.XPTotalHUD then
	dofile(ModPath .. "lua/core.lua")
end

-- Runs before MenuComponentManager creates BLT's notification box, which anchors to this box's top.
Hooks:PostHook(PlayerProfileGuiObject, "init", "XPTotalHUD_profile_init", function(self)
	XPTotalHUD:add_profile_lines(self)
end)
