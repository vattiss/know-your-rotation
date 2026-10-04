local addonName, ns = ...

-- There is no HUD window. The rotation, defense, interrupt, purge, cleanse and
-- weapon cues are glows on the action-bar buttons (Glow.lua). This file only
-- keeps the shared ns.UI table (options panel) and the hooks
-- other modules call after a role / mode change.
ns.UI = ns.UI or {}

local function refreshOptions()
	if ns.RefreshOptions then
		ns.RefreshOptions()
	end
end

ns.UI.RefreshRoles = refreshOptions
ns.UI.RefreshModes = refreshOptions
