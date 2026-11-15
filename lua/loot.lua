if not _G.XPTotalHUD then
	dofile(ModPath .. "lua/core.lua")
end

-- Bags secured, to label the XP some heists pay per bag (First World Bank). The host calls this from
-- secure/server_secure_loot before the loot triggers run the bag's XP element; clients get it from the
-- host before that element's sync, so it comes first everywhere.
Hooks:PreHook(LootManager, "sync_secure_loot", "XPTotalHUD_sync_secure_loot", function(self, carry_id)
	XPTotalHUD:_safe(function()
		XPTotalHUD:log_loot(carry_id)
	end)
end)
