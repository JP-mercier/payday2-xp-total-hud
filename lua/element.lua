if not _G.XPTotalHUD then
	dofile(ModPath .. "lua/core.lua")
end

-- Mission XP comes from Experience elements (on_executed calls mission_xp_award; clients run it through
-- client_on_executed). The element's editor name labels the log line when no objective explains it.
-- Its base amount (before multipliers) names it from the EHI table when that's installed.
Hooks:PreHook(ElementExperience, "on_executed", "XPTotalHUD_ElementExperience_pre", function(self)
	XPTotalHUD._award_element = self._editor_name
	XPTotalHUD._award_base = self._values and self._values.amount
end)

Hooks:PostHook(ElementExperience, "on_executed", "XPTotalHUD_ElementExperience_post", function(self)
	XPTotalHUD._award_element = nil
	XPTotalHUD._award_base = nil
end)
