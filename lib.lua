--[[
	HoloUI v1.2.0 - futuristic UI library for Roblox (Luau)

	Features
	  * Neon / sci-fi look: animated gradient border, glow, scanline, spinning logo
	  * Mobile support: touch dragging, bigger hit areas, floating toggle button,
	    window auto-fits the screen, sliders / pickers lock scrolling while dragging
	  * Animations: open/close, tab slide, ripple, hover, toggles, dropdowns, notifications
	  * Toggle GUI : keybind (default RightShift) + draggable floating button + Window:Toggle()
	  * Lock GUI   : lock button in the title bar + Window:SetLocked(bool)
	  * Elements   : Label, Paragraph, Divider, Button, Toggle, Slider, Input, Dropdown
	                 (single / multi), Keybind, ColorPicker, Progress, Notifications, Tooltips
	  * Config save / load (when the executor exposes writefile / readfile)
	  * Lucide icons: `Icon = "home"` on tabs, sections, elements, notifications and the
	    window / floating button (also accepts rbxassetid:// ids). See the icons section below.

	Quick start
	  local Library = loadstring(readfile("lib.lua"))()      -- or require(ModuleScript)
	  local Window  = Library:CreateWindow({ Title = "HOLO//UI", Subtitle = "demo" })
	  local Tab     = Window:AddTab({ Name = "Main" })
	  local Section = Tab:AddSection("Combat")
	  Section:AddToggle({ Name = "Enabled", Default = true, Flag = "Enabled", Callback = print })
	  Window:AddSettingsTab()

	Sub tabs (dock under the window)
	  local Combat = Window:AddTab({ Name = "Combat", Icon = "swords" })
	  local Aim    = Combat:AddSubTab({ Name = "Aimbot", Icon = "crosshair" })
	  local Vis    = Combat:AddSubTab({ Name = "Visuals" })
	  Aim:AddSection("AIMBOT"):AddToggle({ Name = "Enabled" })
	  (when a tab has sub tabs, put its elements inside the sub tabs)

	Watermark (top-left, under the Roblox top bar)
	  Library:CreateWindow({ ..., Watermark = "HOLO//UI" })   -- or Library:SetWatermark("text" | { Text, Icon } | false)

	Every element can also be added straight to a Tab (without a Section).
	Every element returns an object with :SetValue(v, silent), :GetValue(), :OnChanged(fn).
	Elements with a `Flag` are stored in Library.Flags[flag] / Library.Options[flag].
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local env = type(getgenv) == "function" and getgenv() or nil

local Library = {
	Version = "1.2.0",
	Flags = {},
	Options = {},
	Windows = {},
	AnimSpeed = 1,
	ConfigFolder = "HoloUI",
	IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
	Theme = {
		Background = Color3.fromRGB(9, 11, 19),
		Panel = Color3.fromRGB(14, 17, 29),
		Element = Color3.fromRGB(21, 25, 42),
		ElementHover = Color3.fromRGB(30, 36, 60),
		Stroke = Color3.fromRGB(38, 46, 76),
		Accent = Color3.fromRGB(0, 229, 255),
		Accent2 = Color3.fromRGB(176, 92, 255),
		Text = Color3.fromRGB(232, 240, 255),
		SubText = Color3.fromRGB(135, 148, 185),
		Success = Color3.fromRGB(70, 255, 160),
		Warning = Color3.fromRGB(255, 196, 61),
		Danger = Color3.fromRGB(255, 70, 100),
	},
	_conns = {},
	_themed = {},
	_keybinds = {},
	_spin = {},
}

-- close any previous instance (re-execution)
if env and env.HoloUI and type(env.HoloUI.Unload) == "function" then
	pcall(function() env.HoloUI:Unload() end)
end

local MOBILE = Library.IsMobile
local ROW = MOBILE and 40 or 34
local TEXT_SIZE = MOBILE and 14 or 13
local WHITE = Color3.new(1, 1, 1)
local UIT = Enum.UserInputType

local function pickFont(name, fallback)
	local ok, f = pcall(function() return Enum.Font[name] end)
	return (ok and f) or fallback
end

local Fonts = {
	Title = pickFont("Michroma", Enum.Font.GothamBold),
	Body = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Mono = pickFont("RobotoMono", Enum.Font.Code),
}

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function new(class, props, children)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
		if inst:IsA("GuiButton") then inst.AutoButtonColor = false end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			inst.BackgroundTransparency = 1
			inst.Font = Fonts.Body
			inst.TextSize = TEXT_SIZE
			inst.TextColor3 = Library.Theme.Text
			inst.Text = ""
		end
	end
	local parent
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then parent = v else inst[k] = v end
		end
	end
	if children then
		for _, c in ipairs(children) do c.Parent = inst end
	end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function pad(parent, l, t, r, b)
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, l), PaddingTop = UDim.new(0, t),
		PaddingRight = UDim.new(0, r), PaddingBottom = UDim.new(0, b),
		Parent = parent,
	})
end

local function tween(inst, props, time, style, dir)
	local info = TweenInfo.new(
		(time or 0.2) / math.max(Library.AnimSpeed, 0.05),
		style or Enum.EasingStyle.Quint,
		dir or Enum.EasingDirection.Out
	)
	local tw = TweenService:Create(inst, info, props)
	tw:Play()
	return tw
end

local function safe(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then warn("[HoloUI] callback error: " .. tostring(err)) end
end

local function isPointer(input)
	return input.UserInputType == UIT.MouseButton1 or input.UserInputType == UIT.Touch
end

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(Library._conns, c)
	return c
end

-- theme binding: fn() re-applies accent colours when the theme changes
local function bind(inst, fn)
	table.insert(Library._themed, { inst = inst, fn = fn })
	fn()
end

local function bindColor(inst, prop, key)
	bind(inst, function() inst[prop] = Library.Theme[key] end)
end

local function bindGradient(grad)
	bind(grad, function()
		grad.Color = ColorSequence.new(Library.Theme.Accent, Library.Theme.Accent2)
	end)
end

local function viewport(gui)
	local s = gui and gui.AbsoluteSize or Vector2.zero
	if s.X > 0 and s.Y > 0 then return s end
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

local function getGuiParent()
	if type(gethui) == "function" then
		local ok, h = pcall(gethui)
		if ok and h then return h end
	end
	local core = game:GetService("CoreGui")
	local ok = pcall(function()
		local t = Instance.new("Folder")
		t.Parent = core
		t:Destroy()
	end)
	if ok then return core end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function ripple(parent, x, y)
	local abs = parent.AbsolutePosition
	local c = new("Frame", {
		BackgroundColor3 = Library.Theme.Accent,
		BackgroundTransparency = 0.7,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x - abs.X, y - abs.Y),
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 0,
		Parent = parent,
	})
	corner(c, 999)
	local d = math.max(parent.AbsoluteSize.X, parent.AbsoluteSize.Y) * 2.2
	tween(c, { Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1 }, 0.55)
	task.delay(0.6, function() c:Destroy() end)
end

-- one active drag at a time (window drag, slider, colour picker ...)
local activeDrag
local function startDrag(update, finish)
	activeDrag = { update = update, finish = finish }
end

local function attachDrag(handle, target, canDrag, clamp, state)
	handle.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		if state then state.Moved = false end
		if canDrag and not canDrag() then return end
		local startMouse = input.Position
		local startPos = target.Position
		startDrag(function(pos)
			local d = pos - startMouse
			if state and d.Magnitude > 6 then state.Moved = true end
			local x, y = startPos.X.Offset + d.X, startPos.Y.Offset + d.Y
			if clamp then x, y = clamp(x, y) end
			target.Position = UDim2.fromOffset(x, y)
		end)
	end)
end

local function setScrolling(self, enabled)
	if self.Scroller then self.Scroller.ScrollingEnabled = enabled end
end

----------------------------------------------------------------------
-- icons (Lucide)
----------------------------------------------------------------------
-- Anywhere an `Icon` option is accepted you can pass:
--   "home" | "lucide-home" | "lucide:home"   a Lucide icon name
--   "rbxassetid://123" | 123 | "123"         any Roblox image asset
-- Lucide names are resolved from a registry (name -> sprite). Fill it with
-- Library:LoadIcons(table | url | file path | function), or let it auto-load from
-- Library.IconSources the first time a Lucide name is used (set
-- Library.AutoLoadIcons = false to disable the network fetch).
-- Accepted entry shapes: "rbxassetid://id" | id | { Image, ImageRectSize, ImageRectOffset }
-- (ImageRectPosition works too) | { id, {sx, sy}, {ox, oy} }.

Library.IconSources = { "https://raw.githubusercontent.com/Footagesus/Icons/main/Main-v2.lua" }
Library.AutoLoadIcons = true
Library._icons = (env and env.HoloUI_Icons) or {}
Library._iconsTried = next(Library._icons) ~= nil
if env then env.HoloUI_Icons = Library._icons end

local function assetUrl(v)
	if type(v) == "number" then return string.format("rbxassetid://%d", v) end
	if type(v) == "string" then
		if v:match("^%d+$") then return "rbxassetid://" .. v end
		if v:match("^rbxasset") or v:match("^https?://") then return v end
	end
	return nil
end

local function toVec(v)
	if typeof(v) == "Vector2" then return v end
	if type(v) == "table" then
		local x, y = v.X or v.x or v[1], v.Y or v.y or v[2]
		if type(x) == "number" and type(y) == "number" then return Vector2.new(x, y) end
	end
	return nil
end

local function iconKey(name)
	local k = string.lower(tostring(name)):gsub("^%s+", ""):gsub("%s+$", "")
	k = k:gsub("^lucide[%-:_%.]", ""):gsub("[%s_]+", "-")
	return k
end

-- normalise any supported entry to { Image, ImageRectSize, ImageRectOffset }
local function parseIcon(e, sheets)
	if type(e) == "number" or type(e) == "string" then
		local img = assetUrl(e)
		return img and { Image = img } or nil
	end
	if type(e) ~= "table" then return nil end
	local img, size, offset
	if e[1] ~= nil then
		img, size, offset = e[1], toVec(e[2]), toVec(e[3])
	else
		img = e.Image or e.image or e.id or e.Id or e.ID
		size = toVec(e.ImageRectSize or e.imageRectSize)
		offset = toVec(e.ImageRectOffset or e.ImageRectPosition or e.imageRectOffset or e.imageRectPosition)
	end
	if img == nil then return nil end
	local sheet = sheets and sheets[tostring(img)]
	img = assetUrl(sheet or img)
	if not img then return nil end
	return { Image = img, ImageRectSize = size, ImageRectOffset = offset }
end

-- pick the Lucide set (and spritesheet map) out of whatever a source returned
local function iconSet(root)
	if type(root) ~= "table" then return nil end
	local sheets = root.Spritesheets or root.spritesheets
	for _, k in ipairs({ "lucide", "Lucide", "assets", "Icons" }) do
		local s = root[k]
		if type(s) == "table" then
			if k == "Icons" then s = s.lucide or s.Lucide or s end
			return s, sheets
		end
	end
	return root, sheets
end

local function readSource(src)
	if src:match("^https?://") then
		local ok, body = pcall(function() return game:HttpGet(src) end)
		if ok and type(body) == "string" and body ~= "" then return body end
		local req = type(request) == "function" and request or (type(http_request) == "function" and http_request) or nil
		if req then
			local ok2, res = pcall(req, { Url = src, Method = "GET" })
			if ok2 and type(res) == "table" and type(res.Body) == "string" and res.Body ~= "" then return res.Body end
		end
		return nil
	end
	if type(isfile) == "function" and type(readfile) == "function" then
		local ok, body = pcall(function() if isfile(src) then return readfile(src) end end)
		if ok and type(body) == "string" then return body end
	end
	return nil
end

-- add icons to the registry; returns how many were added
function Library:RegisterIcons(map, sheets)
	local n = 0
	if type(map) ~= "table" then return n end
	for name, entry in pairs(map) do
		if type(name) == "string" then
			local d = parseIcon(entry, sheets)
			if d then
				self._icons[iconKey(name)] = d
				n = n + 1
			end
		end
	end
	return n
end

-- source: table | function returning a table | url | file path (Lua module or JSON)
function Library:LoadIcons(source, sheets)
	local root = source
	if type(source) == "function" then
		local ok, r = pcall(source)
		root = ok and r or nil
	elseif type(source) == "string" then
		local text = readSource(source)
		if not text then return 0 end
		root = nil
		if text:match("^%s*[%{%[]") then
			local ok, r = pcall(function() return HttpService:JSONDecode(text) end)
			root = ok and r or nil
		elseif type(loadstring) == "function" then
			local fn = loadstring(text)
			if fn then
				local ok, r = pcall(fn)
				root = ok and r or nil
			end
		end
	end
	local set, sh = iconSet(root)
	if not set then return 0 end
	local n = self:RegisterIcons(set, sh or sheets)
	if n > 0 then self._iconsTried = true end
	return n
end

function Library:_autoLoadIcons()
	if self._iconsTried then return end
	self._iconsTried = true
	for _, src in ipairs(self.IconSources) do
		if self:LoadIcons(src) > 0 then return end
	end
	warn("[HoloUI] couldn't load the Lucide icon set. Call Library:LoadIcons(<table | url | file>) yourself, or use rbxassetid:// icons.")
end

-- returns { Image, ImageRectSize, ImageRectOffset } or nil
function Library:GetIcon(name)
	if name == nil or name == "" then return nil end
	local direct = parseIcon(name)
	if direct then return direct end
	if type(name) ~= "string" then return nil end
	local key = iconKey(name)
	local hit = self._icons[key]
	if hit then return hit end
	if self.AutoLoadIcons and not self._iconsTried then
		self:_autoLoadIcons()
		return self._icons[key]
	end
	return nil
end

local warnedIcons = {}
local function makeIcon(name, props)
	local d = Library:GetIcon(name)
	if not d then
		local k = tostring(name)
		if not warnedIcons[k] then
			warnedIcons[k] = true
			warn("[HoloUI] unknown icon: " .. k)
		end
		return nil
	end
	props = props or {}
	props.BackgroundTransparency = 1
	props.Image = d.Image
	props.ImageRectSize = d.ImageRectSize or Vector2.zero
	props.ImageRectOffset = d.ImageRectOffset or Vector2.zero
	props.ScaleType = Enum.ScaleType.Fit
	return new("ImageLabel", props)
end

----------------------------------------------------------------------
-- library level: gui, input hooks, notifications, tooltips, theme, config
----------------------------------------------------------------------

function Library:_ensureGui()
	if self.Gui and self.Gui.Parent then return self.Gui end
	local T = self.Theme
	local gui = Instance.new("ScreenGui")
	gui.Name = "HoloUI_" .. HttpService:GenerateGUID(false):sub(1, 8)
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10000
	gui.IgnoreGuiInset = true
	pcall(function()
		if syn and syn.protect_gui then syn.protect_gui(gui) end
	end)
	gui.Parent = getGuiParent()
	self.Gui = gui

	local holder = new("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.new(0, MOBILE and 240 or 300, 1, -24),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Parent = holder,
	})
	self.NotifyHolder = holder

	local tip = new("TextLabel", {
		Name = "Tooltip",
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = T.Panel,
		TextSize = 12,
		Visible = false,
		ZIndex = 1000,
		Parent = gui,
	})
	corner(tip, 5)
	bindColor(stroke(tip, T.Accent, 1), "Color", "Accent")
	pad(tip, 8, 5, 8, 5)
	self._tip = tip

	if not self._hooked then
		self._hooked = true
		self:_hook()
	end
	return gui
end

function Library:_hook()
	connect(UserInputService.InputChanged, function(input)
		if activeDrag and (input.UserInputType == UIT.MouseMovement or input.UserInputType == UIT.Touch) then
			activeDrag.update(input.Position)
		end
	end)

	connect(UserInputService.InputEnded, function(input)
		if activeDrag and isPointer(input) then
			local d = activeDrag
			activeDrag = nil
			if d.finish then d.finish() end
		end
		for i = #self._keybinds, 1, -1 do
			local kb = self._keybinds[i]
			if kb.row.Parent then
				if kb.release then kb.release(input) end
			else
				table.remove(self._keybinds, i)
			end
		end
	end)

	connect(UserInputService.InputBegan, function(input, processed)
		if self._capture then
			if input.UserInputType == UIT.Keyboard then self._capture(input.KeyCode) end
			return
		end
		if processed or input.UserInputType ~= UIT.Keyboard then return end
		for _, w in ipairs(self.Windows) do
			if w.ToggleKey == input.KeyCode then w:Toggle() end
		end
		for i = #self._keybinds, 1, -1 do
			local kb = self._keybinds[i]
			if kb.row.Parent then kb.press(input) else table.remove(self._keybinds, i) end
		end
	end)

	connect(RunService.Heartbeat, function(dt)
		for i = #self._spin, 1, -1 do
			local g = self._spin[i]
			if g.Parent then
				g.Rotation = (g.Rotation + dt * 60) % 360
			else
				table.remove(self._spin, i)
			end
		end
		if self._tip and self._tip.Visible then
			local m = UserInputService:GetMouseLocation()
			self._tip.Position = UDim2.fromOffset(m.X + 14, m.Y + 16)
		end
	end)
end

function Library:_showTip(text)
	if not self._tip then return end
	self._tip.Text = text
	self._tip.Visible = true
	local m = UserInputService:GetMouseLocation()
	self._tip.Position = UDim2.fromOffset(m.X + 14, m.Y + 16)
end

function Library:_hideTip()
	if self._tip then self._tip.Visible = false end
end

function Library:_refreshTheme()
	for i = #self._themed, 1, -1 do
		local e = self._themed[i]
		if e.inst.Parent then
			pcall(e.fn)
		else
			table.remove(self._themed, i)
		end
	end
end

function Library:SetAccent(color, color2)
	if color then self.Theme.Accent = color end
	if color2 then self.Theme.Accent2 = color2 end
	self:_refreshTheme()
end

function Library:Notify(a, b, c)
	local cfg = type(a) == "table" and a or { Title = a, Content = b, Duration = c }
	self:_ensureGui()
	local T = self.Theme
	local colors = {
		Info = T.Accent, Success = T.Success, Warning = T.Warning,
		Error = T.Danger, Danger = T.Danger,
	}
	local color = colors[cfg.Type or "Info"] or T.Accent
	local duration = cfg.Duration or 4
	self._notifId = (self._notifId or 0) + 1

	local wrapper = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = self._notifId,
		Parent = self.NotifyHolder,
	})
	local card = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(1, 40, 0, 0),
		BackgroundColor3 = T.Panel,
		Parent = wrapper,
	})
	corner(card, 8)
	stroke(card, color, 1, 0.35)
	local inner = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = card,
	})
	local notifIcon = cfg.Icon and self:GetIcon(cfg.Icon)
	pad(inner, notifIcon and 38 or 14, 10, 12, 13)
	if notifIcon then
		makeIcon(cfg.Icon, {
			Name = "Icon", ImageColor3 = color, Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(16, 16), Parent = card,
		})
	end
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.Y,
		Text = cfg.Title or "Notification", Font = Fonts.Bold, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LayoutOrder = 1, Parent = inner,
	})
	if cfg.Content and cfg.Content ~= "" then
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.Y,
			Text = cfg.Content, TextColor3 = T.SubText, TextSize = TEXT_SIZE - 1,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true, LayoutOrder = 2, Parent = inner,
		})
	end
	new("Frame", { Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(5, 6), BackgroundColor3 = color, Parent = card })
	local bar = new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = color, Parent = card,
	})
	local button = new("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = card })

	local closed = false
	local function close()
		if closed then return end
		closed = true
		tween(card, { Position = UDim2.new(1, 40, 0, 0) }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.32, function() wrapper:Destroy() end)
	end
	button.Activated:Connect(close)

	tween(card, { Position = UDim2.new(0, 0, 0, 0) }, 0.45, Enum.EasingStyle.Back)
	TweenService:Create(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play()
	task.delay(duration, close)
	return { Close = close }
end

-- config -------------------------------------------------------------

local function serializeOption(opt)
	if opt.Type == "ColorPicker" then return "#" .. opt.Value:ToHex() end
	if opt.Type == "Keybind" then return opt.Value.Name end
	return opt.Value
end

local function deserializeOption(opt, v)
	if opt.Type == "ColorPicker" then return Color3.fromHex(v) end
	if opt.Type == "Keybind" then return Enum.KeyCode[v] end
	return v
end

function Library:SaveConfig(name)
	if type(writefile) ~= "function" then
		return false, "File system is not available in this environment."
	end
	name = (name and name ~= "") and name or "default"
	local data = {}
	for flag, opt in pairs(self.Options) do
		local ok, v = pcall(serializeOption, opt)
		if ok and v ~= nil then data[flag] = v end
	end
	return pcall(function()
		if type(isfolder) == "function" and not isfolder(self.ConfigFolder) then
			makefolder(self.ConfigFolder)
		end
		writefile(self.ConfigFolder .. "/" .. name .. ".json", HttpService:JSONEncode(data))
	end)
end

function Library:LoadConfig(name)
	if type(readfile) ~= "function" then
		return false, "File system is not available in this environment."
	end
	name = (name and name ~= "") and name or "default"
	local path = self.ConfigFolder .. "/" .. name .. ".json"
	if type(isfile) == "function" and not isfile(path) then
		return false, "Config '" .. name .. "' does not exist."
	end
	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
	if not ok then return false, "Config could not be read." end
	for flag, v in pairs(data) do
		local opt = self.Options[flag]
		if opt then
			local okv, value = pcall(deserializeOption, opt, v)
			if okv and value ~= nil then pcall(function() opt:SetValue(value) end) end
		end
	end
	return true
end

function Library:Unload()
	for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
	self._conns, self._themed, self._keybinds, self._spin = {}, {}, {}, {}
	self.Windows, self.Flags, self.Options = {}, {}, {}
	self._wm = nil
	activeDrag = nil
	self._capture = nil
	self._hooked = false
	if self.Gui then
		self.Gui:Destroy()
		self.Gui = nil
	end
	if env and env.HoloUI == self then env.HoloUI = nil end
end

----------------------------------------------------------------------
-- watermark (top-left, below the Roblox top bar)
----------------------------------------------------------------------

function Library:SetWatermark(cfg)
	if cfg == nil or cfg == false then
		if self._wm then self._wm.Frame.Visible = false end
		return
	end
	if type(cfg) == "string" then cfg = { Text = cfg } end
	local gui = self:_ensureGui()
	local T = self.Theme
	if not self._wm or not self._wm.Frame.Parent then
		local frame = new("Frame", {
			Name = "Watermark", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, MOBILE and 30 or 26),
			Position = MOBILE and UDim2.new(0.04, 0, 0.135, 0) or UDim2.fromOffset(14, 44),
			BackgroundColor3 = T.Background, BackgroundTransparency = 0.15, Parent = gui,
		})
		corner(frame, 8)
		local st = stroke(frame, WHITE, 1.2)
		local g = new("UIGradient", { Parent = st })
		bind(g, function()
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Library.Theme.Accent),
				ColorSequenceKeypoint.new(0.5, Library.Theme.Accent2),
				ColorSequenceKeypoint.new(1, Library.Theme.Accent),
			})
		end)
		table.insert(self._spin, g)
		pad(frame, 10, 0, 10, 0)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center, Parent = frame,
		})
		local bar = new("Frame", { Size = UDim2.fromOffset(3, 12), LayoutOrder = 1, Parent = frame })
		corner(bar, 2)
		bindColor(bar, "BackgroundColor3", "Accent")
		local label = new("TextLabel", {
			Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Font = Fonts.Bold, TextSize = 12,
			LayoutOrder = 3, Parent = frame,
		})
		self._wm = { Frame = frame, Label = label }
	end
	local wm = self._wm
	local old = wm.Frame:FindFirstChild("Icon")
	if old then old:Destroy() end
	if cfg.Icon then
		local ic = makeIcon(cfg.Icon, {
			Name = "Icon", Size = UDim2.fromOffset(14, 14), LayoutOrder = 2, Parent = wm.Frame,
		})
		if ic then bindColor(ic, "ImageColor3", "Accent") end
	end
	wm.Label.Text = cfg.Text or "HOLO//UI"
	wm.Frame.Visible = cfg.Visible ~= false
	return wm.Frame
end

function Library:SetWatermarkVisible(v)
	if self._wm then self._wm.Frame.Visible = v and true or false end
end

----------------------------------------------------------------------
-- element base
----------------------------------------------------------------------

local function attachTooltip(obj, text)
	if not text or MOBILE then return end
	obj.MouseEnter:Connect(function() Library:_showTip(text) end)
	obj.MouseLeave:Connect(function() Library:_hideTip() end)
end

local function newObject(cfg, typ, value)
	return {
		Type = typ,
		Value = value,
		Flag = cfg.Flag,
		_listeners = {},
		GetValue = function(self) return self.Value end,
		OnChanged = function(self, fn) table.insert(self._listeners, fn) end,
	}
end

local function register(obj)
	if obj.Flag then
		Library.Options[obj.Flag] = obj
		Library.Flags[obj.Flag] = obj.Value
	end
end

local function fire(obj, cfg, silent)
	if obj.Flag then Library.Flags[obj.Flag] = obj.Value end
	if silent then return end
	safe(cfg.Callback, obj.Value)
	for _, f in ipairs(obj._listeners) do safe(f, obj.Value) end
end

local function nextOrder(self)
	self._order = (self._order or 0) + 1
	return self._order
end

local function makeRow(self, height, cfg)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, height or ROW),
		BackgroundColor3 = Library.Theme.Element,
		ClipsDescendants = true,
		LayoutOrder = nextOrder(self),
		Parent = self.Holder,
	})
	corner(row, 6)
	stroke(row, Library.Theme.Stroke, 1, 0.2)
	if cfg and cfg.Tooltip then attachTooltip(row, cfg.Tooltip) end
	if cfg and cfg.Icon then
		local h = height or ROW
		local ic = makeIcon(cfg.Icon, {
			Name = "Icon", ImageColor3 = cfg.IconColor or Library.Theme.SubText, AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(12, h > ROW and 15 or ROW / 2), Size = UDim2.fromOffset(16, 16), Parent = row,
		})
		if ic then row:SetAttribute("IconInset", 24) end
	end
	return row
end

-- extra left offset a row's label needs when the row has an icon
local function rowInset(row)
	return row:GetAttribute("IconInset") or 0
end

local function rowLabel(row, text, widthOffset)
	local ins = rowInset(row)
	return new("TextLabel", {
		Position = UDim2.fromOffset(12 + ins, 0),
		Size = UDim2.new(1, -((widthOffset or 70) + ins), 1, 0),
		Text = text or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
end

local function hoverRow(row, hit)
	local T = Library.Theme
	hit.MouseEnter:Connect(function() tween(row, { BackgroundColor3 = T.ElementHover }, 0.15) end)
	hit.MouseLeave:Connect(function() tween(row, { BackgroundColor3 = T.Element }, 0.15) end)
end

local function cfgOf(cfg)
	if type(cfg) == "string" then return { Name = cfg } end
	return cfg or {}
end

local Elements = {}

-- Label --------------------------------------------------------------

function Elements:AddLabel(text)
	local lbl = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text or "",
		TextColor3 = Library.Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = nextOrder(self),
		Parent = self.Holder,
	})
	return {
		Instance = lbl,
		SetText = function(_, t) lbl.Text = t end,
		Destroy = function() lbl:Destroy() end,
	}
end

-- Paragraph ----------------------------------------------------------

function Elements:AddParagraph(cfg)
	cfg = cfgOf(cfg)
	local T = Library.Theme
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.Element, LayoutOrder = nextOrder(self), Parent = self.Holder,
	})
	corner(row, 6)
	stroke(row, T.Stroke, 1, 0.2)
	pad(row, 12, 9, 12, 10)
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	local title = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.Y,
		Text = cfg.Title or cfg.Name or "", Font = Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true, LayoutOrder = 1, Parent = row,
	})
	local content = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.Y,
		Text = cfg.Content or "", TextColor3 = T.SubText, TextSize = TEXT_SIZE - 1,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true, LayoutOrder = 2, Parent = row,
	})
	return {
		Instance = row,
		SetTitle = function(_, t) title.Text = t end,
		SetContent = function(_, t) content.Text = t end,
		Destroy = function() row:Destroy() end,
	}
end

-- Divider ------------------------------------------------------------

function Elements:AddDivider()
	local f = new("Frame", {
		Size = UDim2.new(1, 0, 0, 10), BackgroundTransparency = 1,
		LayoutOrder = nextOrder(self), Parent = self.Holder,
	})
	local line = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = WHITE, Parent = f,
	})
	local g = new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = line,
	})
	bindGradient(g)
	return { Instance = f }
end

-- Button -------------------------------------------------------------

function Elements:AddButton(cfg)
	cfg = cfgOf(cfg)
	local T = Library.Theme
	local row = makeRow(self, ROW, cfg)
	local label = rowLabel(row, cfg.Name or "Button", 44)
	local chev = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(14, 14), Text = ">", Font = Fonts.Bold, TextColor3 = T.SubText, Parent = row,
	})
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = row })

	hit.MouseEnter:Connect(function()
		tween(row, { BackgroundColor3 = T.ElementHover }, 0.15)
		tween(chev, { TextColor3 = Library.Theme.Accent, Position = UDim2.new(1, -8, 0.5, 0) }, 0.15)
	end)
	hit.MouseLeave:Connect(function()
		tween(row, { BackgroundColor3 = T.Element }, 0.15)
		tween(chev, { TextColor3 = T.SubText, Position = UDim2.new(1, -12, 0.5, 0) }, 0.15)
	end)
	hit.InputBegan:Connect(function(input)
		if isPointer(input) then ripple(row, input.Position.X, input.Position.Y) end
	end)
	hit.Activated:Connect(function() safe(cfg.Callback) end)

	return {
		Instance = row,
		SetText = function(_, t) label.Text = t end,
		Fire = function() safe(cfg.Callback) end,
		Destroy = function() row:Destroy() end,
	}
end

-- Toggle -------------------------------------------------------------

function Elements:AddToggle(cfg)
	cfg = cfgOf(cfg)
	local T = Library.Theme
	local row = makeRow(self, ROW, cfg)
	local obj = newObject(cfg, "Toggle", cfg.Default and true or false)
	rowLabel(row, cfg.Name or "Toggle", 70)

	local TW, TH = MOBILE and 46 or 40, MOBILE and 24 or 20
	local track = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(TW, TH), BackgroundColor3 = T.Stroke, Parent = row,
	})
	corner(track, TH)
	local trackStroke = stroke(track, T.Stroke, 1)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(TH - 6, TH - 6), BackgroundColor3 = T.SubText, Parent = track,
	})
	corner(knob, 99)
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = row })
	hoverRow(row, hit)

	local function render(animate)
		local on = obj.Value
		local goal = {
			pos = on and UDim2.new(1, -(TH - 3), 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			track = on and Library.Theme.Accent or T.Stroke,
			knob = on and WHITE or T.SubText,
			stroke = on and Library.Theme.Accent2 or T.Stroke,
		}
		if animate then
			tween(knob, { Position = goal.pos, BackgroundColor3 = goal.knob }, 0.25, Enum.EasingStyle.Back)
			tween(track, { BackgroundColor3 = goal.track }, 0.2)
			tween(trackStroke, { Color = goal.stroke }, 0.2)
		else
			knob.Position, knob.BackgroundColor3 = goal.pos, goal.knob
			track.BackgroundColor3, trackStroke.Color = goal.track, goal.stroke
		end
	end
	bind(track, function() render(false) end)

	function obj:SetValue(v, silent)
		v = v and true or false
		if self.Value == v then return end
		self.Value = v
		render(true)
		fire(self, cfg, silent)
	end
	function obj:Toggle() self:SetValue(not self.Value) end
	hit.Activated:Connect(function() obj:SetValue(not obj.Value) end)

	obj.Instance = row
	register(obj)
	return obj
end

-- Slider -------------------------------------------------------------

function Elements:AddSlider(cfg)
	cfg = cfgOf(cfg)
	local T = Library.Theme
	local min, max = cfg.Min or 0, cfg.Max or 100
	local inc = cfg.Increment or 1
	local dec = #(tostring(inc):match("%.(%d+)") or "")
	local H = MOBILE and 58 or 50
	local row = makeRow(self, H, cfg)
	local obj = newObject(cfg, "Slider", math.clamp(cfg.Default or min, min, max))

	new("TextLabel", {
		Position = UDim2.fromOffset(12 + rowInset(row), 6), Size = UDim2.new(1, -(110 + rowInset(row)), 0, 18), Text = cfg.Name or "Slider",
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})
	local valueLbl = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(94, 18),
		Font = Fonts.Mono, TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
	})
	bindColor(valueLbl, "TextColor3", "Accent")

	local trackH = MOBILE and 8 or 6
	local track = new("Frame", {
		Position = UDim2.new(0, 12, 1, -(trackH + 14)), Size = UDim2.new(1, -24, 0, trackH),
		BackgroundColor3 = T.Background, Parent = row,
	})
	corner(track, 99)
	local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = WHITE, Parent = track })
	corner(fill, 99)
	bindGradient(new("UIGradient", { Parent = fill }))
	local K = MOBILE and 16 or 12
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(K, K), BackgroundColor3 = WHITE, ZIndex = 2, Parent = track,
	})
	corner(knob, 99)
	bindColor(stroke(knob, T.Accent, 2), "Color", "Accent")
	local hit = new("TextButton", {
		Position = UDim2.fromScale(0, 0.45), Size = UDim2.fromScale(1, 0.55), ZIndex = 3, Parent = row,
	})
	hoverRow(row, hit)

	local function fmt(v) return string.format("%." .. dec .. "f", v) end
	local function render(animate)
		local a = (max == min) and 0 or (obj.Value - min) / (max - min)
		valueLbl.Text = fmt(obj.Value) .. (cfg.Suffix or "")
		if animate then
			tween(fill, { Size = UDim2.new(a, 0, 1, 0) }, 0.08, Enum.EasingStyle.Linear)
			tween(knob, { Position = UDim2.new(a, 0, 0.5, 0) }, 0.08, Enum.EasingStyle.Linear)
		else
			fill.Size = UDim2.new(a, 0, 1, 0)
			knob.Position = UDim2.new(a, 0, 0.5, 0)
		end
	end

	function obj:SetValue(v, silent)
		v = math.clamp(tonumber(v) or min, min, max)
		v = min + math.floor((v - min) / inc + 0.5) * inc
		v = math.clamp(tonumber(fmt(v)) or min, min, max)
		self.Value = v
		render(true)
		fire(self, cfg, silent)
	end

	local function setFromX(x)
		local w = track.AbsoluteSize.X
		if w <= 0 then return end
		obj:SetValue(min + (max - min) * math.clamp((x - track.AbsolutePosition.X) / w, 0, 1))
	end
	hit.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		setScrolling(self, false)
		tween(knob, { Size = UDim2.fromOffset(K + 4, K + 4) }, 0.15)
		setFromX(input.Position.X)
		startDrag(function(pos) setFromX(pos.X) end, function()
			setScrolling(self, true)
			tween(knob, { Size = UDim2.fromOffset(K, K) }, 0.15)
		end)
	end)

	render(false)
	obj.Instance = row
	register(obj)
	return obj
end

-- Input --------------------------------------------------------------

function Elements:AddInput(cfg)
	cfg = cfgOf(cfg)
	local T = Library.Theme
	local row = makeRow(self, ROW, cfg)
	local obj = newObject(cfg, "Input", cfg.Numeric and (tonumber(cfg.Default) or 0) or tostring(cfg.Default or ""))

	new("TextLabel", {
		Position = UDim2.fromOffset(12 + rowInset(row), 0), Size = UDim2.new(0.4, -(12 + rowInset(row)), 1, 0), Text = cfg.Name or "Input",
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})
	local boxFrame = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0.58, 0, 1, -10), BackgroundColor3 = T.Background, Parent = row,
	})
	corner(boxFrame, 5)
	local boxStroke = stroke(boxFrame, T.Stroke, 1)
	local box = new("TextBox", {
		Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), Text = tostring(obj.Value),
		PlaceholderText = cfg.Placeholder or "", PlaceholderColor3 = T.SubText, ClearTextOnFocus = cfg.ClearOnFocus == true,
		TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true, TextSize = TEXT_SIZE - 1, Parent = boxFrame,
	})

	box.Focused:Connect(function() tween(boxStroke, { Color = Library.Theme.Accent }, 0.2) end)
	box.FocusLost:Connect(function(enter)
		tween(boxStroke, { Color = T.Stroke }, 0.2)
		if cfg.RequireEnter and not enter then
			box.Text = tostring(obj.Value)
			return
		end
		if cfg.Numeric then
			local n = tonumber(box.Text)
			obj:SetValue(n or obj.Value)
		else
			obj:SetValue(box.Text)
		end
	end)

	function obj:SetValue(v, silent)
		if cfg.Numeric then self.Value = tonumber(v) or self.Value else self.Value = tostring(v) end
		box.Text = tostring(self.Value)
		fire(self, cfg, silent)
	end

	obj.Instance = row
	register(obj)
	return obj
end

-- Dropdown -----------------------------------------------------------

function Elements:AddDropdown(cfg)
	cfg = cfgOf(cfg)
	local T = Library.Theme
	local multi = cfg.Multi == true
	local OPT = MOBILE and 34 or 28
	local MAXVIS = cfg.MaxVisible or 5
	local options = {}
	for _, o in ipairs(cfg.Options or cfg.Values or {}) do table.insert(options, tostring(o)) end

	local row = makeRow(self, ROW, cfg)
	local obj = newObject(cfg, "Dropdown", multi and {} or nil)
	local selected = {}
	local open = false
	local buttons = {}

	new("TextLabel", {
		Position = UDim2.fromOffset(12 + rowInset(row), 0), Size = UDim2.new(0.45, -(12 + rowInset(row)), 0, ROW), Text = cfg.Name or "Dropdown",
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})
	local valueLbl = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -30, 0, 0), Size = UDim2.new(0.55, -36, 0, ROW),
		Text = "None", TextColor3 = T.SubText, TextSize = TEXT_SIZE - 1,
		TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})
	local arrow = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -16, 0, ROW / 2), Size = UDim2.fromOffset(14, 14),
		Text = ">", Font = Fonts.Bold, TextColor3 = T.SubText, Rotation = 90, Parent = row,
	})
	local head = new("TextButton", { Size = UDim2.new(1, 0, 0, ROW), ZIndex = 2, Parent = row })
	hoverRow(row, head)
	local list = new("ScrollingFrame", {
		Position = UDim2.new(0, 6, 0, ROW), Size = UDim2.new(1, -12, 0, 0), BackgroundTransparency = 1,
		ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = row,
	})
	bindColor(list, "ScrollBarImageColor3", "Accent")
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	local function isOn(name)
		if multi then return selected[name] == true end
		return obj.Value == name
	end
	local function currentArray()
		local arr = {}
		for _, o in ipairs(options) do
			if selected[o] then table.insert(arr, o) end
		end
		return arr
	end
	local function renderValue()
		if multi then
			local arr = currentArray()
			valueLbl.Text = #arr == 0 and "None" or table.concat(arr, ", ")
		else
			valueLbl.Text = obj.Value or "None"
		end
	end
	local function paint(b)
		local on = isOn(b.name)
		tween(b.btn, { BackgroundTransparency = on and 0.3 or 1 }, 0.15)
		tween(b.label, { TextColor3 = on and Library.Theme.Accent or T.Text }, 0.15)
	end
	local function paintAll()
		for _, b in ipairs(buttons) do paint(b) end
	end
	local function listHeight() return math.min(#options, MAXVIS) * (OPT + 3) end
	local function resize()
		list.Size = UDim2.new(1, -12, 0, listHeight())
		tween(row, { Size = UDim2.new(1, 0, 0, open and (ROW + listHeight() + 8) or ROW) }, 0.25)
		tween(arrow, { Rotation = open and -90 or 90 }, 0.25)
	end

	local function build()
		for _, b in ipairs(buttons) do b.btn:Destroy() end
		buttons = {}
		for i, name in ipairs(options) do
			local btn = new("TextButton", {
				Size = UDim2.new(1, 0, 0, OPT), BackgroundColor3 = T.ElementHover, BackgroundTransparency = 1,
				LayoutOrder = i, Parent = list,
			})
			corner(btn, 5)
			local label = new("TextLabel", {
				Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), Text = name,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn,
			})
			local b = { btn = btn, label = label, name = name }
			table.insert(buttons, b)
			btn.MouseEnter:Connect(function()
				if not isOn(name) then tween(btn, { BackgroundTransparency = 0.6 }, 0.12) end
			end)
			btn.MouseLeave:Connect(function() paint(b) end)
			btn.Activated:Connect(function()
				if multi then
					selected[name] = (not selected[name]) or nil
					obj.Value = currentArray()
				else
					obj.Value = name
					open = false
					resize()
				end
				paintAll()
				renderValue()
				fire(obj, cfg)
			end)
			paint(b)
		end
	end

	function obj:SetValue(v, silent)
		if multi then
			selected = {}
			if type(v) == "table" then
				for k, val in pairs(v) do
					if type(k) == "number" then selected[tostring(val)] = true
					elseif val then selected[tostring(k)] = true end
				end
			elseif v ~= nil then
				selected[tostring(v)] = true
			end
			self.Value = currentArray()
		else
			self.Value = v ~= nil and tostring(v) or nil
		end
		paintAll()
		renderValue()
		fire(self, cfg, silent)
	end

	function obj:SetOptions(list2, keep)
		options = {}
		for _, o in ipairs(list2 or {}) do table.insert(options, tostring(o)) end
		if not keep then
			selected = {}
			self.Value = multi and {} or nil
		else
			local found = {}
			for _, o in ipairs(options) do found[o] = true end
			for k in pairs(selected) do
				if not found[k] then selected[k] = nil end
			end
			if multi then
				self.Value = currentArray()
			elseif self.Value and not found[self.Value] then
				self.Value = nil
			end
		end
		build()
		renderValue()
		if self.Flag then Library.Flags[self.Flag] = self.Value end
		if open then resize() end
	end

	head.Activated:Connect(function()
		open = not open
		resize()
	end)

	build()
	if cfg.Default ~= nil then obj:SetValue(cfg.Default, true) else renderValue() end
	obj.Instance = row
	register(obj)
	return obj
end

-- Keybind ------------------------------------------------------------

function Elements:AddKeybind(cfg)
	cfg = cfgOf(cfg)
	local T = Library.Theme
	local mode = cfg.Mode or "Press"
	local row = makeRow(self, ROW, cfg)
	local obj = newObject(cfg, "Keybind", cfg.Default or Enum.KeyCode.Unknown)
	obj.State = false
	rowLabel(row, cfg.Name or "Keybind", 120)

	local function keyName(k)
		return (k == nil or k == Enum.KeyCode.Unknown) and "None" or k.Name
	end
	local boxFrame = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, 104, 1, -10), BackgroundColor3 = T.Background, Parent = row,
	})
	corner(boxFrame, 5)
	local kStroke = stroke(boxFrame, T.Stroke, 1)
	local btn = new("TextButton", {
		Size = UDim2.fromScale(1, 1), Text = keyName(obj.Value), Font = Fonts.Mono, TextSize = 12, Parent = boxFrame,
	})
	hoverRow(row, btn)

	local listening = false
	local function stopListening()
		listening = false
		Library._capture = nil
		btn.Text = keyName(obj.Value)
		tween(kStroke, { Color = T.Stroke }, 0.2)
	end

	function obj:SetValue(key, silent)
		self.Value = key or Enum.KeyCode.Unknown
		btn.Text = keyName(self.Value)
		if self.Flag then Library.Flags[self.Flag] = self.Value end
		if silent then return end
		safe(cfg.ChangedCallback, self.Value)
		for _, f in ipairs(self._listeners) do safe(f, self.Value) end
	end

	btn.Activated:Connect(function()
		if listening then
			stopListening()
			return
		end
		listening = true
		btn.Text = "..."
		tween(kStroke, { Color = Library.Theme.Accent }, 0.2)
		Library._capture = function(key)
			if key == Enum.KeyCode.Escape then
				stopListening()
			elseif key == Enum.KeyCode.Backspace then
				obj:SetValue(Enum.KeyCode.Unknown)
				stopListening()
			else
				obj:SetValue(key)
				stopListening()
			end
		end
	end)

	table.insert(Library._keybinds, {
		row = row,
		press = function(input)
			if obj.Value == Enum.KeyCode.Unknown or input.KeyCode ~= obj.Value then return end
			if mode == "Toggle" then
				obj.State = not obj.State
				safe(cfg.Callback, obj.State)
			elseif mode == "Hold" then
				obj.State = true
				safe(cfg.Callback, true)
			else
				safe(cfg.Callback)
			end
		end,
		release = function(input)
			if mode == "Hold" and obj.State and input.KeyCode == obj.Value then
				obj.State = false
				safe(cfg.Callback, false)
			end
		end,
	})

	obj.Instance = row
	register(obj)
	return obj
end

-- ColorPicker --------------------------------------------------------

function Elements:AddColorPicker(cfg)
	cfg = cfgOf(cfg)
	local T = Library.Theme
	local PH = MOBILE and 130 or 110
	local row = makeRow(self, ROW, cfg)
	local obj = newObject(cfg, "ColorPicker", cfg.Default or Library.Theme.Accent)
	local h, s, v = obj.Value:ToHSV()
	local open = false

	rowLabel(row, cfg.Name or "Color", 70)
	local swatch = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0, ROW / 2),
		Size = UDim2.fromOffset(36, 18), BackgroundColor3 = obj.Value, Parent = row,
	})
	corner(swatch, 4)
	local swStroke = stroke(swatch, WHITE, 1, 0.6)
	local head = new("TextButton", { Size = UDim2.new(1, 0, 0, ROW), ZIndex = 2, Parent = row })
	hoverRow(row, head)

	-- saturation / value square
	local sv = new("Frame", {
		Position = UDim2.new(0, 10, 0, ROW + 2), Size = UDim2.new(1, -44, 0, PH),
		BackgroundColor3 = Color3.fromHSV(h, 1, 1), Parent = row,
	})
	corner(sv, 5)
	local white = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, ZIndex = 1, Parent = sv })
	corner(white, 5)
	new("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
	local black = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 2, Parent = sv })
	corner(black, 5)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black })
	local svCursor = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, ZIndex = 3, Parent = sv,
	})
	corner(svCursor, 99)
	stroke(svCursor, WHITE, 2)
	local svHit = new("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = sv })

	-- hue bar
	local hue = new("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, ROW + 2), Size = UDim2.new(0, 18, 0, PH),
		BackgroundColor3 = WHITE, Parent = row,
	})
	corner(hue, 5)
	local kps = {}
	for i = 0, 6 do table.insert(kps, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1))) end
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(kps), Parent = hue })
	local hueCursor = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 4, 0, 4), BackgroundColor3 = WHITE, ZIndex = 3, Parent = hue,
	})
	corner(hueCursor, 2)
	stroke(hueCursor, Color3.new(0, 0, 0), 1, 0.4)
	local hueHit = new("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = hue })

	-- hex input
	local hexFrame = new("Frame", {
		Position = UDim2.new(0, 10, 0, ROW + PH + 10), Size = UDim2.new(1, -20, 0, 26), BackgroundColor3 = T.Background, Parent = row,
	})
	corner(hexFrame, 5)
	local hexStroke = stroke(hexFrame, T.Stroke, 1)
	local hexBox = new("TextBox", {
		Size = UDim2.fromScale(1, 1), Font = Fonts.Mono, TextSize = 12, ClearTextOnFocus = false, Parent = hexFrame,
	})

	local function apply(silent)
		local c = Color3.fromHSV(h, s, v)
		obj.Value = c
		swatch.BackgroundColor3 = c
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svCursor.Position = UDim2.fromScale(s, 1 - v)
		hueCursor.Position = UDim2.fromScale(0.5, h)
		if not hexBox:IsFocused() then hexBox.Text = "#" .. c:ToHex():upper() end
		fire(obj, cfg, silent)
	end

	function obj:SetValue(c, silent)
		local h0, s0, v0 = c:ToHSV()
		if s0 > 0 then h = h0 end
		s, v = s0, v0
		apply(silent)
	end

	local function updateSV(pos)
		local ap, as = sv.AbsolutePosition, sv.AbsoluteSize
		if as.X <= 0 or as.Y <= 0 then return end
		s = math.clamp((pos.X - ap.X) / as.X, 0, 1)
		v = 1 - math.clamp((pos.Y - ap.Y) / as.Y, 0, 1)
		apply()
	end
	local function updateHue(pos)
		local ap, as = hue.AbsolutePosition, hue.AbsoluteSize
		if as.Y <= 0 then return end
		h = math.clamp((pos.Y - ap.Y) / as.Y, 0, 1)
		apply()
	end
	svHit.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		setScrolling(self, false)
		updateSV(input.Position)
		startDrag(updateSV, function() setScrolling(self, true) end)
	end)
	hueHit.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		setScrolling(self, false)
		updateHue(input.Position)
		startDrag(updateHue, function() setScrolling(self, true) end)
	end)

	hexBox.Focused:Connect(function() tween(hexStroke, { Color = Library.Theme.Accent }, 0.2) end)
	hexBox.FocusLost:Connect(function()
		tween(hexStroke, { Color = T.Stroke }, 0.2)
		local ok, c = pcall(Color3.fromHex, hexBox.Text)
		if ok and c then obj:SetValue(c) else hexBox.Text = "#" .. obj.Value:ToHex():upper() end
	end)

	head.Activated:Connect(function()
		open = not open
		tween(row, { Size = UDim2.new(1, 0, 0, open and (ROW + PH + 46) or ROW) }, 0.3)
		tween(swStroke, { Transparency = open and 0 or 0.6 }, 0.2)
	end)

	apply(true)
	obj.Instance = row
	register(obj)
	return obj
end

-- Progress -----------------------------------------------------------

function Elements:AddProgress(cfg)
	cfg = cfgOf(cfg)
	local T = Library.Theme
	local min, max = cfg.Min or 0, cfg.Max or 100
	local row = makeRow(self, MOBILE and 52 or 46, cfg)
	local obj = newObject(cfg, "Progress", math.clamp(cfg.Default or min, min, max))

	new("TextLabel", {
		Position = UDim2.fromOffset(12 + rowInset(row), 5), Size = UDim2.new(1, -(80 + rowInset(row)), 0, 18), Text = cfg.Name or "Progress",
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})
	local valueLbl = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 5), Size = UDim2.fromOffset(60, 18),
		Font = Fonts.Mono, TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
	})
	bindColor(valueLbl, "TextColor3", "Accent")
	local track = new("Frame", {
		Position = UDim2.new(0, 12, 1, -16), Size = UDim2.new(1, -24, 0, 6), BackgroundColor3 = T.Background, Parent = row,
	})
	corner(track, 99)
	local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = WHITE, Parent = track })
	corner(fill, 99)
	bindGradient(new("UIGradient", { Parent = fill }))

	local function render(animate)
		local a = (max == min) and 0 or (obj.Value - min) / (max - min)
		valueLbl.Text = string.format("%d%%", math.floor(a * 100 + 0.5))
		if animate then
			tween(fill, { Size = UDim2.new(a, 0, 1, 0) }, 0.35)
		else
			fill.Size = UDim2.new(a, 0, 1, 0)
		end
	end
	function obj:SetValue(val, silent)
		self.Value = math.clamp(tonumber(val) or min, min, max)
		render(true)
		fire(self, cfg, silent)
	end

	render(false)
	obj.Instance = row
	register(obj)
	return obj
end

----------------------------------------------------------------------
-- Tab / Section
----------------------------------------------------------------------

local Tab = {}
setmetatable(Tab, { __index = Elements })
Tab.__index = Tab

local Section = {}
setmetatable(Section, { __index = Elements })
Section.__index = Section

function Tab:AddSection(title, icon)
	if type(title) == "table" then icon, title = title.Icon, title.Title or title.Name end
	local T = Library.Theme
	local sec = setmetatable({ Window = self.Window, Scroller = self.Scroller, _order = 0 }, Section)
	local frame = new("Frame", {
		Name = "Section", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.Panel, LayoutOrder = nextOrder(self), Parent = self.Holder,
	})
	corner(frame, 8)
	stroke(frame, T.Stroke, 1, 0.3)
	pad(frame, 8, 8, 8, 8)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })

	local header = new("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 0, Parent = frame })
	local bar = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(3, 12), Parent = header })
	corner(bar, 2)
	bindColor(bar, "BackgroundColor3", "Accent")
	local lblX = 10
	if icon then
		local ic = makeIcon(icon, {
			Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(14, 14), Parent = header,
		})
		if ic then
			bindColor(ic, "ImageColor3", "Accent")
			lblX = 30
		end
	end
	local lbl = new("TextLabel", {
		Position = UDim2.fromOffset(lblX, 0), Size = UDim2.new(1, -lblX, 1, 0), Text = string.upper(title or "Section"),
		Font = Fonts.Title, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Parent = header,
	})
	bindColor(lbl, "TextColor3", "Accent")

	sec.Holder = frame
	sec.Instance = frame
	return sec
end

function Tab:Select()
	self.Window:SelectTab(self)
end

function Tab:SelectSubTab(sub)
	if self._activeSub == sub then return end
	local prev = self._activeSub
	if prev then
		prev._page.Visible = false
		prev._setSelected(false)
	end
	self._activeSub = sub
	sub._setSelected(true)
	if self.Selected then
		sub._page.Position = UDim2.new(0, 0, 0, 14)
		sub._page.Visible = true
		tween(sub._page, { Position = UDim2.new(0, 0, 0, 0) }, 0.3)
	end
end

-- sub tab: shown as a button in the dock below the window
function Tab:AddSubTab(cfg)
	assert(not self._isSub, "[HoloUI] sub tabs cannot be nested")
	cfg = cfgOf(cfg)
	local W = self.Window
	local T = Library.Theme
	local sub = setmetatable({ Window = W, Name = cfg.Name or "Sub", _order = 0, _isSub = true, _parent = self }, Tab)
	self._subs = self._subs or {}

	local btn = new("TextButton", {
		Name = sub.Name, Size = UDim2.fromOffset(0, W._dockH - 8), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = T.Element, BackgroundTransparency = 1, LayoutOrder = #self._subs + 1,
		Visible = false, Parent = W._dock,
	})
	corner(btn, 7)
	pad(btn, 12, 0, 12, 0)
	local inner = new("Frame", {
		Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = btn,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center, Parent = inner,
	})
	local subIcon
	if cfg.Icon then
		subIcon = makeIcon(cfg.Icon, {
			Name = "Icon", ImageColor3 = cfg.IconColor or T.SubText, Size = UDim2.fromOffset(14, 14), LayoutOrder = 1, Parent = inner,
		})
	end
	local label = new("TextLabel", {
		Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = sub.Name, Font = Fonts.Bold,
		TextSize = TEXT_SIZE - 1, TextColor3 = T.SubText, LayoutOrder = 2, Parent = inner,
	})
	local underline = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.fromOffset(0, 2), Parent = btn,
	})
	corner(underline, 1)
	bindColor(underline, "BackgroundColor3", "Accent")

	local page = new("ScrollingFrame", {
		Name = sub.Name .. "SubPage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		ScrollBarThickness = MOBILE and 4 or 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, Parent = W._content,
	})
	bindColor(page, "ScrollBarImageColor3", "Accent")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	pad(page, 10, 10, 12, 10)

	sub.Holder, sub.Scroller, sub._page, sub.Instance, sub._btn = page, page, page, btn, btn
	sub._setSelected = function(on)
		sub.Selected = on
		tween(btn, { BackgroundTransparency = on and 0.35 or 1 }, 0.2)
		tween(underline, { Size = UDim2.fromOffset(on and 16 or 0, 2) }, 0.25, Enum.EasingStyle.Back)
		tween(label, { TextColor3 = on and Library.Theme.Accent or T.SubText }, 0.2)
		if subIcon and not cfg.IconColor then
			tween(subIcon, { ImageColor3 = on and Library.Theme.Accent or T.SubText }, 0.2)
		end
	end
	bind(label, function()
		if sub.Selected then
			label.TextColor3 = Library.Theme.Accent
			if subIcon and not cfg.IconColor then subIcon.ImageColor3 = Library.Theme.Accent end
		end
	end)
	btn.MouseEnter:Connect(function()
		if not sub.Selected then tween(btn, { BackgroundTransparency = 0.7 }, 0.15) end
	end)
	btn.MouseLeave:Connect(function()
		if not sub.Selected then tween(btn, { BackgroundTransparency = 1 }, 0.15) end
	end)
	btn.Activated:Connect(function()
		W:SelectTab(self)
		self:SelectSubTab(sub)
	end)
	sub.Select = function()
		W:SelectTab(self)
		self:SelectSubTab(sub)
	end

	table.insert(self._subs, sub)
	if not self._activeSub then
		self._activeSub = sub
		sub._setSelected(true)
		if self.Selected then
			self._page.Visible = false
			sub._page.Visible = true
		end
	end
	W._hasSubs = true
	if W._fit then W._fit() end
	W:_refreshDock()
	return sub
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------

local Window = {}
Window.__index = Window

function Window:SetVisible(v)
	self.Visible = v and true or false
	if self.Visible then
		self.Root.Visible = true
		tween(self._fade, { BackgroundTransparency = 1 }, 0.3)
		tween(self._scale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
	else
		tween(self._fade, { BackgroundTransparency = 0 }, 0.18)
		tween(self._scale, { Scale = 0.9 }, 0.2)
		task.delay(0.22, function()
			if not self.Visible and self.Root.Parent then self.Root.Visible = false end
		end)
	end
end

function Window:Show() self:SetVisible(true) end
function Window:Hide() self:SetVisible(false) end
function Window:Toggle() self:SetVisible(not self.Visible) end

function Window:SetLocked(v, silent)
	v = v and true or false
	local changed = self.Locked ~= v
	self.Locked = v
	if self._renderLock then self._renderLock() end
	if self._lockToggle then self._lockToggle:SetValue(v, true) end
	if changed and not silent then
		Library:Notify({
			Title = v and "Window locked" or "Window unlocked",
			Content = v and "Dragging is disabled." or "You can drag the window again.",
			Duration = 2, Type = v and "Success" or "Info",
		})
	end
end

function Window:ToggleLock() self:SetLocked(not self.Locked) end

function Window:_refreshDock()
	if not self._dock then return end
	local cur = self.CurrentTab
	local has = cur ~= nil and cur._subs ~= nil and #cur._subs > 0
	for _, t in ipairs(self.Tabs) do
		if t._subs then
			for _, s in ipairs(t._subs) do s._btn.Visible = (t == cur) end
		end
	end
	self._dock.Visible = has and not self.Minimized
end

function Window:SetMinimized(v)
	self.Minimized = v and true or false
	self:_refreshDock()
	local size = self.FullSize
	if self.Minimized then
		tween(self.Root, { Size = UDim2.fromOffset(size.X, self._topbar) }, 0.3)
		task.delay(0.3, function()
			if self.Minimized then self._body.Visible = false end
		end)
	else
		self._body.Visible = true
		tween(self.Root, { Size = UDim2.fromOffset(size.X, size.Y) }, 0.3)
	end
end

function Window:SetToggleKey(key) self.ToggleKey = key end

function Window:SetToggleButtonVisible(v)
	self._tbVisible = v and true or false
	self._toggleButton.Visible = self._tbVisible
end

function Window:SetTitle(text) self._title.Text = text end

function Window:Destroy()
	for i, w in ipairs(Library.Windows) do
		if w == self then table.remove(Library.Windows, i) break end
	end
	self.Root:Destroy()
	self._toggleButton:Destroy()
end

function Window:SelectTab(tab)
	if self.CurrentTab == tab then return end
	local prev = self.CurrentTab
	if prev then
		prev._page.Visible = false
		if prev._activeSub then prev._activeSub._page.Visible = false end
		prev._setSelected(false)
	end
	self.CurrentTab = tab
	tab._setSelected(true)
	local target = tab._page
	if tab._subs and #tab._subs > 0 and tab._activeSub then
		tab._page.Visible = false
		target = tab._activeSub._page
	end
	target.Position = UDim2.new(0, 0, 0, 14)
	target.Visible = true
	tween(target, { Position = UDim2.new(0, 0, 0, 0) }, 0.3)
	self:_refreshDock()
end

function Window:AddTab(cfg)
	cfg = cfgOf(cfg)
	local T = Library.Theme
	local tab = setmetatable({ Window = self, Name = cfg.Name or "Tab", _order = 0 }, Tab)

	local btn = new("TextButton", {
		Name = tab.Name, Size = UDim2.new(1, 0, 0, MOBILE and 40 or 36), BackgroundColor3 = T.Element,
		BackgroundTransparency = 1, LayoutOrder = #self.Tabs + 1, Parent = self._tabList,
	})
	corner(btn, 6)
	local indicator = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(3, 0), Parent = btn,
	})
	corner(indicator, 2)
	bindColor(indicator, "BackgroundColor3", "Accent")
	local xOff = 14
	local tabIcon
	if cfg.Icon then
		tabIcon = makeIcon(cfg.Icon, {
			Name = "Icon", ImageColor3 = cfg.IconColor or T.SubText, AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(16, 16), Parent = btn,
		})
		if tabIcon then xOff = 34 end
	end
	local label = new("TextLabel", {
		Position = UDim2.fromOffset(xOff, 0), Size = UDim2.new(1, -xOff - 6, 1, 0), Text = tab.Name, Font = Fonts.Bold,
		TextColor3 = T.SubText, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn,
	})

	local page = new("ScrollingFrame", {
		Name = tab.Name .. "Page", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		ScrollBarThickness = MOBILE and 4 or 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, Parent = self._content,
	})
	bindColor(page, "ScrollBarImageColor3", "Accent")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	pad(page, 10, 10, 12, 10)

	tab.Holder = page
	tab.Scroller = page
	tab._page = page
	tab.Instance = btn

	tab._setSelected = function(on)
		tab.Selected = on
		tween(btn, { BackgroundTransparency = on and 0.35 or 1 }, 0.2)
		tween(indicator, { Size = UDim2.fromOffset(3, on and 18 or 0) }, 0.25, Enum.EasingStyle.Back)
		tween(label, { TextColor3 = on and Library.Theme.Accent or T.SubText }, 0.2)
		if tabIcon and not cfg.IconColor then
			tween(tabIcon, { ImageColor3 = on and Library.Theme.Accent or T.SubText }, 0.2)
		end
	end
	bind(label, function()
		if tab.Selected then
			label.TextColor3 = Library.Theme.Accent
			if tabIcon and not cfg.IconColor then tabIcon.ImageColor3 = Library.Theme.Accent end
		end
	end)

	btn.MouseEnter:Connect(function()
		if not tab.Selected then tween(btn, { BackgroundTransparency = 0.7 }, 0.15) end
	end)
	btn.MouseLeave:Connect(function()
		if not tab.Selected then tween(btn, { BackgroundTransparency = 1 }, 0.15) end
	end)
	btn.Activated:Connect(function() self:SelectTab(tab) end)

	table.insert(self.Tabs, tab)
	if not self.CurrentTab then self:SelectTab(tab) end
	return tab
end

function Window:AddSettingsTab(icon)
	local tab = self:AddTab({ Name = "Settings", Icon = icon })
	local ui = tab:AddSection("Interface")
	ui:AddKeybind({
		Name = "Toggle UI key", Default = self.ToggleKey, Flag = "HoloUI_ToggleKey",
		ChangedCallback = function(k)
			if k ~= Enum.KeyCode.Unknown then self.ToggleKey = k end
		end,
	})
	self._lockToggle = ui:AddToggle({
		Name = "Lock window position", Default = self.Locked, Flag = "HoloUI_Lock",
		Callback = function(v) self:SetLocked(v) end,
	})
	ui:AddToggle({
		Name = "Floating toggle button", Default = self._tbVisible, Flag = "HoloUI_ToggleButton",
		Callback = function(v) self:SetToggleButtonVisible(v) end,
	})
	ui:AddColorPicker({
		Name = "Accent color", Default = Library.Theme.Accent, Flag = "HoloUI_Accent",
		Callback = function(c) Library:SetAccent(c) end,
	})
	ui:AddColorPicker({
		Name = "Secondary color", Default = Library.Theme.Accent2, Flag = "HoloUI_Accent2",
		Callback = function(c) Library:SetAccent(nil, c) end,
	})
	ui:AddSlider({
		Name = "Animation speed", Min = 0.25, Max = 3, Default = Library.AnimSpeed, Increment = 0.25, Suffix = "x",
		Flag = "HoloUI_AnimSpeed", Callback = function(v) Library.AnimSpeed = v end,
	})
	ui:AddButton({ Name = "Unload UI", Callback = function() Library:Unload() end })

	local cfgSec = tab:AddSection("Configuration")
	local nameInput = cfgSec:AddInput({ Name = "Config name", Default = "default", Placeholder = "default" })
	cfgSec:AddButton({
		Name = "Save config",
		Callback = function()
			local ok, err = Library:SaveConfig(nameInput.Value)
			Library:Notify({
				Title = ok and "Config saved" or "Save failed", Content = ok and nameInput.Value or tostring(err),
				Type = ok and "Success" or "Error", Duration = 3,
			})
		end,
	})
	cfgSec:AddButton({
		Name = "Load config",
		Callback = function()
			local ok, err = Library:LoadConfig(nameInput.Value)
			Library:Notify({
				Title = ok and "Config loaded" or "Load failed", Content = ok and nameInput.Value or tostring(err),
				Type = ok and "Success" or "Error", Duration = 3,
			})
		end,
	})
	return tab
end

----------------------------------------------------------------------
-- CreateWindow
----------------------------------------------------------------------

function Library:CreateWindow(cfg)
	cfg = cfg or {}
	local gui = self:_ensureGui()
	local T = self.Theme

	local W = setmetatable({
		Tabs = {},
		Locked = cfg.Locked == true,
		Visible = true,
		Minimized = false,
		ToggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift,
	}, Window)

	local sz = cfg.Size
	if typeof(sz) == "UDim2" then sz = Vector2.new(sz.X.Offset, sz.Y.Offset) end
	sz = sz or Vector2.new(MOBILE and 520 or 600, MOBILE and 300 or 400)
	local TOPBAR = MOBILE and 48 or 44
	local SIDEBAR = MOBILE and 100 or 132
	local DOCK_H = MOBILE and 42 or 38
	local TB, TBS -- floating toggle button (created further down)
	W._topbar = TOPBAR
	W._dockH = DOCK_H

	local vp = viewport(gui)
	local w0 = math.min(sz.X, vp.X - 16)
	local h0 = math.min(sz.Y, vp.Y - 16)
	W.FullSize = Vector2.new(w0, h0)

	local Root = new("Frame", {
		Name = "Window", BackgroundTransparency = 1, Size = UDim2.fromOffset(w0, h0),
		Position = UDim2.fromOffset(math.floor((vp.X - w0) / 2), math.floor((vp.Y - h0) / 2)), Parent = gui,
	})
	local Scaler = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = Root,
	})
	local scale = new("UIScale", { Scale = 0.85, Parent = Scaler })

	local shadow = new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 56, 1, 56),
		BackgroundTransparency = 1, Image = "rbxassetid://5028857084", ImageTransparency = 0.72, ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(24, 24, 276, 276), ZIndex = 0, Parent = Scaler,
	})
	bindColor(shadow, "ImageColor3", "Accent")

	local Main = new("Frame", {
		Name = "Main", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE,
		ClipsDescendants = true, Active = true, Parent = Scaler,
	})
	corner(Main, 10)
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(17, 21, 38), Color3.fromRGB(8, 10, 18)), Rotation = 135, Parent = Main,
	})
	local border = stroke(Main, WHITE, 1.5)
	local borderGrad = new("UIGradient", { Parent = border })
	bind(borderGrad, function()
		borderGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Library.Theme.Accent),
			ColorSequenceKeypoint.new(0.5, Library.Theme.Accent2),
			ColorSequenceKeypoint.new(1, Library.Theme.Accent),
		})
	end)
	table.insert(self._spin, borderGrad)

	-- top bar ---------------------------------------------------------
	local Top = new("Frame", { Name = "TopBar", Size = UDim2.new(1, 0, 0, TOPBAR), BackgroundTransparency = 1, Parent = Main })
	local logo = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 22, 0.5, 0), Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = WHITE, Rotation = 45, Parent = Top,
	})
	corner(logo, 2)
	bindGradient(new("UIGradient", { Parent = logo }))
	TweenService:Create(logo, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 405 }):Play()
	if cfg.Icon then
		local ic = makeIcon(cfg.Icon, {
			Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 22, 0.5, 0),
			Size = UDim2.fromOffset(18, 18), Parent = Top,
		})
		if ic then
			bindColor(ic, "ImageColor3", "Accent")
			logo.Visible = false
		end
	end

	local hasSub = cfg.Subtitle ~= nil and cfg.Subtitle ~= ""
	local title = new("TextLabel", {
		Position = UDim2.fromOffset(42, hasSub and 6 or 0), Size = UDim2.new(1, -190, 0, hasSub and 18 or TOPBAR),
		Text = cfg.Title or "HOLO//UI", Font = Fonts.Title, TextSize = 12, TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = Top,
	})
	bindGradient(new("UIGradient", { Parent = title }))
	W._title = title
	if hasSub then
		new("TextLabel", {
			Position = UDim2.fromOffset(42, 24), Size = UDim2.new(1, -190, 0, 14), Text = cfg.Subtitle, TextColor3 = T.SubText,
			TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = Top,
		})
	end

	local BTN = MOBILE and 32 or 28
	local btnHolder = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(0, BTN),
		AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = Top,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center, Parent = btnHolder,
	})
	local function headerButton(text, order)
		local b = new("TextButton", {
			Size = UDim2.fromOffset(BTN, BTN), BackgroundColor3 = T.Element, Text = text, Font = Fonts.Bold,
			TextSize = 16, TextColor3 = T.SubText, LayoutOrder = order, Parent = btnHolder,
		})
		corner(b, 6)
		stroke(b, T.Stroke, 1, 0.2)
		b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = T.ElementHover }, 0.15) end)
		b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = T.Element }, 0.15) end)
		return b
	end

	-- lock button with a drawn padlock
	local lockBtn = headerButton("", 1)
	local shackle = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, -4), Size = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 1, Parent = lockBtn,
	})
	corner(shackle, 4)
	local shackleStroke = stroke(shackle, T.SubText, 2)
	local body = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, -3), Size = UDim2.fromOffset(12, 9),
		BackgroundColor3 = T.SubText, Parent = lockBtn,
	})
	corner(body, 2)
	W._renderLock = function()
		local locked = W.Locked
		local col = locked and Library.Theme.Accent or T.SubText
		tween(shackle, { Position = UDim2.new(0.5, 0, 0.5, locked and -4 or -7) }, 0.25, Enum.EasingStyle.Back)
		tween(shackleStroke, { Color = col }, 0.2)
		tween(body, { BackgroundColor3 = col }, 0.2)
	end
	bind(lockBtn, W._renderLock)
	lockBtn.Activated:Connect(function() W:SetLocked(not W.Locked) end)
	attachTooltip(lockBtn, "Lock / unlock window position")

	local minBtn = headerButton("-", 2)
	minBtn.Activated:Connect(function() W:SetMinimized(not W.Minimized) end)
	attachTooltip(minBtn, "Minimize")
	local closeBtn = headerButton("x", 3)
	closeBtn.Activated:Connect(function()
		W:Hide()
		if MOBILE then
			W:SetToggleButtonVisible(true)
		else
			Library:Notify({
				Title = "Window hidden", Content = "Press " .. W.ToggleKey.Name .. " to open it again.",
				Duration = 2.5,
			})
		end
	end)
	attachTooltip(closeBtn, "Hide window")

	-- animated scanline under the top bar
	local scan = new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = WHITE, Parent = Top,
	})
	local scanGrad = new("UIGradient", {
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = scan,
	})
	bindGradient(scanGrad)
	TweenService:Create(
		scanGrad, TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0.3),
		{ Offset = Vector2.new(1, 0) }
	):Play()
	new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = T.Stroke, BackgroundTransparency = 0.5, ZIndex = 0, Parent = Top,
	})

	-- body: sidebar + content -------------------------------------------
	local Body = new("Frame", {
		Name = "Body", Position = UDim2.fromOffset(0, TOPBAR), Size = UDim2.new(1, 0, 1, -TOPBAR),
		BackgroundTransparency = 1, Parent = Main,
	})
	W._body = Body

	local Sidebar = new("Frame", { Size = UDim2.new(0, SIDEBAR, 1, 0), BackgroundTransparency = 1, Parent = Body })
	new("Frame", {
		Position = UDim2.new(1, -1, 0, 8), Size = UDim2.new(0, 1, 1, -16), BackgroundColor3 = T.Stroke,
		BackgroundTransparency = 0.4, Parent = Sidebar,
	})
	local tabList = new("ScrollingFrame", {
		Position = UDim2.fromOffset(6, 8), Size = UDim2.new(1, -13, 1, -46), BackgroundTransparency = 1,
		ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = Sidebar,
	})
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabList })
	W._tabList = tabList

	local footer = new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, -1, 0, 34),
		BackgroundTransparency = 1, Parent = Sidebar,
	})
	local dot = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = T.Success, Parent = footer,
	})
	corner(dot, 99)
	TweenService:Create(
		dot, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.8 }
	):Play()
	local lp = Players.LocalPlayer
	new("TextLabel", {
		Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -36, 1, 0), Text = lp and lp.DisplayName or "User",
		TextColor3 = T.SubText, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = footer,
	})

	local content = new("Frame", {
		Position = UDim2.fromOffset(SIDEBAR, 0), Size = UDim2.new(1, -SIDEBAR, 1, 0), BackgroundTransparency = 1,
		ClipsDescendants = true, Parent = Body,
	})
	W._content = content

	-- fade overlay used by the open / close animation (drawn above everything)
	local fade = new("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Background, BackgroundTransparency = 0, ZIndex = 100, Parent = Main,
	})
	corner(fade, 10)

	W.Root, W.Main, W._scale, W._fade = Root, Main, scale, fade

	-- sub tab dock: sits just under the window and auto-shrinks to fit the screen
	local dock = new("Frame", {
		Name = "SubTabDock", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 8),
		Size = UDim2.fromOffset(0, DOCK_H), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.Background,
		Visible = false, Parent = Scaler,
	})
	corner(dock, 10)
	bindColor(stroke(dock, T.Accent, 1.2, 0.35), "Color", "Accent")
	pad(dock, 4, 4, 4, 4)
	local dockLayout = new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center, Parent = dock,
	})
	local dockScale = new("UIScale", { Parent = dock })
	W._dock = dock
	local function fitDock()
		local natural = dockLayout.AbsoluteContentSize.X + 8
		local avail = viewport(gui).X - 16
		local sc = natural > 0 and math.clamp(avail / natural, 0.5, 1) or 1
		if math.abs(dockScale.Scale - sc) > 0.001 then dockScale.Scale = sc end
	end
	dockLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitDock)

	-- dragging the window --------------------------------------------------
	local function clampWindow(x, y)
		local v = viewport(gui)
		return math.clamp(x, 60 - W.FullSize.X, v.X - 60), math.clamp(y, 0, math.max(v.Y - TOPBAR, 0))
	end
	attachDrag(Top, Root, function() return not W.Locked end, clampWindow)

	local function fit()
		local v = viewport(gui)
		local reserve = W._hasSubs and (DOCK_H + 10) or 0 -- room for the sub tab dock
		local w = math.min(sz.X, v.X - 16)
		local h = math.min(sz.Y, v.Y - 16 - reserve)
		W.FullSize = Vector2.new(w, h)
		Root.Size = UDim2.fromOffset(w, W.Minimized and TOPBAR or h)
		local p = Root.Position
		local x, y = clampWindow(p.X.Offset, p.Y.Offset)
		if reserve > 0 and not W.Minimized then
			y = math.max(math.min(y, v.Y - h - reserve - 8), 0)
		end
		Root.Position = UDim2.fromOffset(x, y)
		if TB then -- keep the floating button on screen after a resize / rotation
			local tp = TB.Position
			TB.Position = UDim2.fromOffset(
				math.clamp(tp.X.Offset, 0, math.max(v.X - TBS, 0)),
				math.clamp(tp.Y.Offset, 0, math.max(v.Y - TBS, 0))
			)
		end
		fitDock()
	end
	W._fit = fit
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	-- floating toggle button (draggable, great for mobile) -------------------
	TBS = MOBILE and 52 or 44
	local showTB = cfg.ToggleButton
	if showTB == nil then showTB = MOBILE end
	W._tbVisible = showTB and true or false
	TB = new("TextButton", {
		Name = "ToggleButton", Size = UDim2.fromOffset(TBS, TBS), Position = UDim2.fromOffset(16, math.floor(vp.Y * 0.35)),
		BackgroundColor3 = T.Background, Visible = W._tbVisible, Active = true, Parent = gui,
	})
	corner(TB, 99)
	local tbStroke = stroke(TB, WHITE, 2)
	local tbGrad = new("UIGradient", { Parent = tbStroke })
	bind(tbGrad, function()
		tbGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Library.Theme.Accent),
			ColorSequenceKeypoint.new(0.5, Library.Theme.Accent2),
			ColorSequenceKeypoint.new(1, Library.Theme.Accent),
		})
	end)
	table.insert(self._spin, tbGrad)
	local tbLogo = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = WHITE, Rotation = 45, Parent = TB,
	})
	corner(tbLogo, 3)
	bindGradient(new("UIGradient", { Parent = tbLogo }))
	TweenService:Create(tbLogo, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 405 }):Play()
	if cfg.Icon then
		local ic = makeIcon(cfg.Icon, {
			Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(22, 22), Parent = TB,
		})
		if ic then
			bindColor(ic, "ImageColor3", "Accent")
			tbLogo.Visible = false
		end
	end
	local tbScale = new("UIScale", { Parent = TB })
	TB.InputBegan:Connect(function(input)
		if isPointer(input) then tween(tbScale, { Scale = 0.9 }, 0.12) end
	end)
	TB.InputEnded:Connect(function(input)
		if isPointer(input) then tween(tbScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back) end
	end)
	local tbState = { Moved = false }
	attachDrag(TB, TB, function() return not W.Locked end, function(x, y)
		local v = viewport(gui)
		return math.clamp(x, 0, v.X - TBS), math.clamp(y, 0, v.Y - TBS)
	end, tbState)
	TB.Activated:Connect(function()
		if tbState.Moved then return end
		W:Toggle()
	end)
	W._toggleButton = TB

	table.insert(self.Windows, W)

	if cfg.Watermark then self:SetWatermark(cfg.Watermark) end

	-- opening animation
	tween(scale, { Scale = 1 }, 0.55, Enum.EasingStyle.Back)
	tween(fade, { BackgroundTransparency = 1 }, 0.55)

	return W
end

if env then env.HoloUI = Library end

return Library
