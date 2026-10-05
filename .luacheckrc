-- luacheck settings for the GitHub "Check" workflow.
std = "lua51"
max_line_length = false
-- The WoW API and Blizzard UI are globals the addon reads or sets; checking
-- them would be all noise. 212 = unused argument (event handler signatures).
-- addonName is part of the standard file header (local addonName, ns = ...).
ignore = { "11.", "12.", "13.", "212", "211/addonName" }
