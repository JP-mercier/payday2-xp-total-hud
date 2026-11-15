if not _G.XPTotalHUD then
	dofile(ModPath .. "lua/core.lua")
end

-- Objectives for the log. Clients run the same objective elements as the host, so these fire for
-- everyone. Calls with load_data restore objectives when dropping in and aren't logged.

for _, name in ipairs({ "activate_objective", "activate_objective_countdown" }) do
	Hooks:PostHook(ObjectivesManager, name, "XPTotalHUD_" .. name, function(self, id, load_data)
		if load_data then
			return
		end
		local objective = id and self._objectives[id]
		if objective and self._active_objectives[id] == objective then
			XPTotalHUD:_safe(function()
				XPTotalHUD:log_objective("new", objective.text)
			end)
		end
	end)
end

-- Sub-objectives ("Email", "Voicemail" under "Find dirt on Alice Rainey") often give their own XP.
Hooks:PostHook(ObjectivesManager, "complete_sub_objective", "XPTotalHUD_complete_sub_objective", function(self, id, sub_id, load_data)
	if load_data then
		return
	end
	local objective = id and self._objectives[id]
	local sub = objective and objective.sub_objectives[sub_id]
	if sub and sub.completed then
		XPTotalHUD:_safe(function()
			XPTotalHUD:log_objective("sub", sub.text)
		end)
	end
end)

-- Objectives with an amount ("bag 4 of 8") call these once per step and only finish on the last one,
-- so the line is added when the objective leaves the active list.
local completing = {}

for _, name in ipairs({ "complete_objective", "complete_objective_countdown" }) do
	Hooks:PreHook(ObjectivesManager, name, "XPTotalHUD_" .. name .. "_pre", function(self, id, load_data)
		completing[name] = not load_data and id ~= nil and self._active_objectives[id] ~= nil and id or nil
	end)

	Hooks:PostHook(ObjectivesManager, name, "XPTotalHUD_" .. name .. "_post", function(self, id, load_data)
		local active_id = completing[name]
		completing[name] = nil
		if active_id ~= nil and active_id == id and not self._active_objectives[id] then
			local objective = self._objectives[id]
			XPTotalHUD:_safe(function()
				XPTotalHUD:log_objective("done", objective and objective.text)
			end)
		end
	end)
end
