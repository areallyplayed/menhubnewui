-- HoloUI demo: shows every element.
-- Load the library from a file in your executor's workspace folder:
local Library = loadstring(readfile("lib.lua"))()
-- (or: local Library = require(path.to.ModuleScript))

local Window = Library:CreateWindow({
	Title = "HOLO//UI",
	Subtitle = "v" .. Library.Version,
	Size = Vector2.new(600, 400),
	ToggleKey = Enum.KeyCode.RightShift, -- toggle GUI (desktop)
	-- ToggleButton = true,              -- floating button; on by default for mobile
	-- Locked = true,                    -- start with the window locked
})

----------------------------------------------------------------------
local Main = Window:AddTab({ Name = "Main" })

local Basics = Main:AddSection("Basics")
Basics:AddLabel("Drag the title bar to move. Use the padlock to lock the position.")
Basics:AddParagraph({ Title = "Paragraph", Content = "Auto-sizing text block for longer descriptions." })
Basics:AddButton({
	Name = "Button",
	Tooltip = "Fires a notification",
	Callback = function()
		Library:Notify({ Title = "Hello", Content = "Button clicked.", Type = "Success", Duration = 3 })
	end,
})
Basics:AddToggle({
	Name = "Toggle", Default = true, Flag = "demo_toggle",
	Callback = function(v) print("toggle:", v) end,
})
Basics:AddDivider()
Basics:AddSlider({
	Name = "Slider", Min = 0, Max = 100, Default = 40, Increment = 1, Suffix = "%", Flag = "demo_slider",
	Callback = function(v) print("slider:", v) end,
})
Basics:AddSlider({ Name = "Decimal slider", Min = 0, Max = 2, Default = 1, Increment = 0.05, Flag = "demo_decimal" })

local Inputs = Main:AddSection("Inputs")
Inputs:AddInput({
	Name = "Text input", Placeholder = "type here...", Flag = "demo_input",
	Callback = function(text) print("input:", text) end,
})
Inputs:AddInput({ Name = "Number input", Numeric = true, Default = 16, RequireEnter = true })
Inputs:AddDropdown({
	Name = "Dropdown", Options = { "Head", "Torso", "Legs", "Arms" }, Default = "Head", Flag = "demo_dropdown",
	Callback = function(v) print("dropdown:", v) end,
})
Inputs:AddDropdown({
	Name = "Multi dropdown", Multi = true, Options = { "Red", "Green", "Blue", "Cyan", "Magenta", "Yellow", "Black" },
	Default = { "Cyan" }, Flag = "demo_multi",
	Callback = function(list) print("multi:", table.concat(list, ", ")) end,
})
Inputs:AddKeybind({
	Name = "Keybind (press)", Default = Enum.KeyCode.F, Flag = "demo_key",
	Callback = function() Library:Notify({ Title = "Keybind", Content = "F was pressed", Duration = 2 }) end,
})
Inputs:AddKeybind({
	Name = "Keybind (toggle)", Default = Enum.KeyCode.G, Mode = "Toggle",
	Callback = function(state) print("keybind state:", state) end,
})
Inputs:AddColorPicker({
	Name = "Color picker", Default = Color3.fromRGB(255, 0, 120), Flag = "demo_color",
	Callback = function(c) print("color:", c) end,
})

----------------------------------------------------------------------
local Status = Window:AddTab({ Name = "Status" })
local Info = Status:AddSection("Progress")
local bar = Info:AddProgress({ Name = "Loading", Min = 0, Max = 100, Default = 0 })
Info:AddButton({
	Name = "Animate progress",
	Callback = function()
		task.spawn(function()
			for i = 0, 100, 10 do
				bar:SetValue(i)
				task.wait(0.15)
			end
			Library:Notify({ Title = "Done", Content = "Progress finished.", Type = "Success" })
		end)
	end,
})
Status:AddSection("Notifications"):AddButton({
	Name = "Show all notification types",
	Callback = function()
		Library:Notify({ Title = "Info", Content = "Something happened.", Type = "Info" })
		Library:Notify({ Title = "Success", Content = "It worked.", Type = "Success" })
		Library:Notify({ Title = "Warning", Content = "Careful now.", Type = "Warning" })
		Library:Notify({ Title = "Error", Content = "It broke.", Type = "Error" })
	end,
})

-- Settings tab: toggle key, lock, floating button, accent colors, animation speed, config save/load, unload
Window:AddSettingsTab()

Library:Notify({
	Title = "HoloUI loaded",
	Content = Library.IsMobile and "Tap the floating button to show / hide." or "Press RightShift to show / hide.",
	Duration = 4,
})
