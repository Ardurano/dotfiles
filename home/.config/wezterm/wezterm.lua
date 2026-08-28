local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15.0
config.window_background_opacity = 0.70
config.macos_window_background_blur = 50
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"

-- CTRL+1..8 jump straight to a tab, CTRL+9 to the last one - same shape as the
-- built-in SUPER+<n> bindings, which stay in place alongside these.
config.keys = {}
for i = 1, 8 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "CTRL",
		action = wezterm.action.ActivateTab(i - 1),
	})
end
table.insert(config.keys, {
	key = "9",
	mods = "CTRL",
	action = wezterm.action.ActivateTab(-1),
})

-- CTRL+Tab stays WezTerm's own tab cycling, but CTRL+SHIFT+Tab is handed down to
-- the running program: herdr binds it to next_tab. Without this, WezTerm's default
-- CTRL+SHIFT+Tab (previous tab) would swallow the chord before herdr saw it.
table.insert(config.keys, {
	key = "Tab",
	mods = "CTRL|SHIFT",
	action = wezterm.action.DisableDefaultAssignment,
})

-- Dim unfocused windows so the focused one is obvious at a glance.
local UNFOCUSED_FOREGROUND_TEXT_HSB = { hue = 1.0, saturation = 0.25, brightness = 0.45 }
-- Tracks window_background_opacity a fixed step below it, so the unfocused state
-- stays visibly dimmer. Move both together if the base opacity changes.
local UNFOCUSED_WINDOW_BACKGROUND_OPACITY = 0.50

-- get_config_overrides() hands back a copy, so the current value is never the
-- same table we last stored; compare the fields instead of the identity.
local function same_text_hsb(actual, expected)
	if actual == nil or expected == nil then
		return actual == expected
	end
	return actual.hue == expected.hue
		and actual.saturation == expected.saturation
		and actual.brightness == expected.brightness
end

wezterm.on("window-focus-changed", function(window)
	local overrides = window:get_config_overrides() or {}
	local text_hsb, opacity
	if not window:is_focused() then
		text_hsb = UNFOCUSED_FOREGROUND_TEXT_HSB
		opacity = UNFOCUSED_WINDOW_BACKGROUND_OPACITY
	end

	-- Only write when one of the two values we own actually changes; a redundant
	-- set_config_overrides() call would trigger another config reload.
	if same_text_hsb(overrides.foreground_text_hsb, text_hsb) and overrides.window_background_opacity == opacity then
		return
	end

	overrides.foreground_text_hsb = text_hsb
	overrides.window_background_opacity = opacity
	window:set_config_overrides(overrides)
end)

return config
