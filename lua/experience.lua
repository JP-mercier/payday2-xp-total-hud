if not _G.XPTotalHUD then
	dofile(ModPath .. "lua/core.lua")
end

-- Objectives award XP through mission_xp_award (host and clients alike). Comparing the total before
-- and after gives what the award is worth after every multiplier, like XP Notifier's "XP gained".
local total_before

Hooks:PreHook(ExperienceManager, "mission_xp_award", "XPTotalHUD_mission_xp_award_pre", function(self, amount)
	total_before = XPTotalHUD:tracking() and XPTotalHUD:current_total() or nil
end)

Hooks:PostHook(ExperienceManager, "mission_xp_award", "XPTotalHUD_mission_xp_award_post", function(self, amount)
	if not total_before then
		return
	end
	local total_after = XPTotalHUD:current_total()
	if total_after then
		XPTotalHUD:add_gain(total_after - total_before)
	end
	total_before = nil
end)
