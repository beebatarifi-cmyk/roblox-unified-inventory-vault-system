-- InventoryUI.lua
-- Place this script inside StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local GuiSvc = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
player:WaitForChild("Backpack")

local function getBackpack()
	return player:FindFirstChildOfClass("Backpack")
end

-- Hide default backpack UI
task.spawn(function()
	for _ = 1, 10 do
		if pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end) then
			break
		end
		task.wait(0.5)
	end
end)

local remotesFolder = ReplicatedStorage:FindFirstChild("InventoryRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "InventoryRemotes"
	remotesFolder.Parent = ReplicatedStorage
	for _, name in ipairs({"Drop", "Pickup", "Give", "Notify", "Deposit", "Withdraw", "VaultSync", "MoneyDeposit", "MoneyWithdraw"}) do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = remotesFolder
	end
end

local DropEv = remotesFolder:WaitForChild("Drop")
local PickupEv = remotesFolder:WaitForChild("Pickup")
local GiveEv = remotesFolder:WaitForChild("Give")
local NotifyEv = remotesFolder:WaitForChild("Notify")
local DepositEv = remotesFolder:WaitForChild("Deposit")
local WithdrawEv = remotesFolder:WaitForChild("Withdraw")
local VaultSyncEv = remotesFolder:WaitForChild("VaultSync")
local MoneyDepositEv = remotesFolder:WaitForChild("MoneyDeposit")
local MoneyWithdrawEv = remotesFolder:WaitForChild("MoneyWithdraw")

local dropsFolder = workspace:FindFirstChild("DroppedItems")
if not dropsFolder then
	dropsFolder = Instance.new("Folder")
	dropsFolder.Name = "DroppedItems"
	dropsFolder.Parent = workspace
end

local PURPLE = Color3.fromRGB(123, 75, 245)
local PANEL = Color3.fromRGB(21, 15, 43)
local SLOT = Color3.fromRGB(36, 28, 71)
local STROKE = Color3.fromRGB(48, 39, 92)
local FONT = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)

local function new(className, props, parent)
	local obj = Instance.new(className)
	for k, v in pairs(props or {}) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function corner(obj, radius)
	new("UICorner", {CornerRadius = UDim.new(0, radius)}, obj)
end

local function label(props, parent)
	props.BackgroundTransparency = 1
	props.FontFace = FONT
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	return new("TextLabel", props, parent)
end

local layout = {{}, {}}
local hotbar = {}
local selected = nil
local hidden = {}
local pendingSlot = nil
local refs, gridSlots, hotSlots = {}, {{}, {}}, {}
local vaultItems = {}
local render

local gui = new("ScreenGui", {
	Name = "InventoryUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = false,
	DisplayOrder = 10,
}, player:WaitForChild("PlayerGui"))

local toastGui = new("ScreenGui", {
	Name = "InventoryToast",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 20,
}, player.PlayerGui)

local bg = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BorderSizePixel = 0,
	BackgroundColor3 = Color3.new(1, 1, 1),
}, gui)

new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(74, 34, 168)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(42, 19, 102)),
		ColorSequenceKeypoint.new(0.65, Color3.fromRGB(21, 11, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 6, 32)),
	}),
}, bg)

local root = new("Frame", {
	Size = UDim2.fromOffset(1012, 600),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1,
}, bg)

local uiScale = new("UIScale", {}, root)
local function fit()
	local v = workspace.CurrentCamera.ViewportSize
	uiScale.Scale = math.min(v.X / 1060, v.Y / 640, 1.5)
end
fit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

local toast = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -40),
	Size = UDim2.fromOffset(280, 36),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.1,
	Visible = false,
}, toastGui)
corner(toast, 8)
new("UIStroke", {Color = PURPLE, Thickness = 1.5}, toast)
local toastLbl = label({Size = UDim2.fromScale(1, 1), TextSize = 16}, toast)
local toastToken = 0
local function showToast(text)
	toastToken += 1
	local my = toastToken
	toastLbl.Text = text
	toast.Visible = true
	task.delay(1.8, function()
		if my == toastToken then
			toast.Visible = false
		end
	end)
end
NotifyEv.OnClientEvent:Connect(showToast)

local function makeSlot(parent, kind, p, i)
	local f = new("Frame", {BackgroundColor3 = SLOT, BorderSizePixel = 0, Active = true}, parent)
	corner(f, 7)
	local stroke = new("UIStroke", {Color = STROKE, Thickness = 1}, f)
	local icon = new("ImageLabel", {BackgroundTransparency = 1, Size = UDim2.fromScale(0.84, 0.76), Position = UDim2.fromScale(0.08, 0.03), ScaleType = Enum.ScaleType.Fit, Visible = false}, f)
	local vp = new("ViewportFrame", {BackgroundTransparency = 1, Size = UDim2.fromScale(0.88, 0.78), Position = UDim2.fromScale(0.06, 0.02), Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1), Visible = false}, f)
	local txt = label({Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.25), TextScaled = true, Visible = false, TextColor3 = Color3.fromRGB(200, 195, 230)}, f)
	local qty = label({Size = UDim2.fromOffset(30, 14), Position = UDim2.new(1, -36, 0, 4), Text = "1x", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, Visible = false, ZIndex = 3}, f)
	local tagLbl = label({Size = UDim2.new(1, -6, 0, 12), Position = UDim2.new(0, 3, 1, -22), TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, Visible = false, ZIndex = 4, Text = ""}, f)
	local bar = new("Frame", {Size = UDim2.new(0.86, 0, 0, 3), Position = UDim2.new(0.07, 0, 1, -8), BackgroundColor3 = PURPLE, BorderSizePixel = 0, Visible = false, ZIndex = 2}, f)
	corner(bar, 999)
	local num
	if kind == "hot" then
		num = label({Size = UDim2.fromOffset(20, 18), Position = UDim2.fromOffset(7, 3), Text = tostring(i), TextSize = 17, TextColor3 = Color3.fromRGB(183, 176, 214), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5}, f)
	end

	local r = {frame = f, kind = kind, p = p, i = i, icon = icon, vp = vp, txt = txt, qty = qty, tag = tagLbl, tagLbl = tagLbl, bar = bar, num = num, stroke = stroke}
	table.insert(refs, r)
	return r
end

local function makePanel(x, title)
	local panel = new("Frame", {Size = UDim2.fromOffset(440, 600), Position = UDim2.fromOffset(x, 0), BackgroundColor3 = PANEL, BorderSizePixel = 0}, root)
	corner(panel, 10)
	new("UIStroke", {Color = Color3.fromRGB(44, 35, 84), Thickness = 1}, panel)
	label({Size = UDim2.fromOffset(200, 22), Position = UDim2.fromOffset(20, 20), Text = title, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left}, panel)
	local w = label({Size = UDim2.fromOffset(200, 22), Position = UDim2.fromOffset(220, 20), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right}, panel)
	new("Frame", {Size = UDim2.fromOffset(400, 1), Position = UDim2.fromOffset(20, 50), BackgroundColor3 = Color3.fromRGB(74, 58, 150), BorderSizePixel = 0}, panel)
	local track = new("Frame", {Size = UDim2.fromOffset(400, 6), Position = UDim2.fromOffset(20, 58), BackgroundColor3 = Color3.fromRGB(13, 8, 32), BorderSizePixel = 0}, panel)
	corner(track, 4)
	local fill = new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = PURPLE, BorderSizePixel = 0}, track)
	corner(fill, 4)
	local grid = new("Frame", {Size = UDim2.fromOffset(400, 400), Position = UDim2.fromOffset(20, 92), BackgroundTransparency = 1}, panel)
	new("UIGridLayout", {CellSize = UDim2.fromOffset(72, 72), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder}, grid)
	return panel, grid, w, fill
end

local leftPanel, grid1, w1, fill1 = makePanel(0, string.upper(player.Name))
local rightPanel, grid2, w2, fill2 = makePanel(572, "الخزنة")
local weightUI = {{w1, fill1}, {w2, fill2}}

for p, grid in ipairs({grid1, grid2}) do
	for i = 1, 25 do
		local s = makeSlot(grid, "grid", p, i)
		s.frame.LayoutOrder = i
		gridSlots[p][i] = s
	end
end

local mid = new("Frame", {Size = UDim2.fromOffset(112, 600), Position = UDim2.fromOffset(450, 0), BackgroundTransparency = 1}, root)
local moneyBar = new("Frame", {Size = UDim2.fromOffset(400, 42), Position = UDim2.fromOffset(20, 68), BackgroundColor3 = Color3.fromRGB(13, 8, 32), BorderSizePixel = 0}, rightPanel)
corner(moneyBar, 6)
local cashLbl = label({Size = UDim2.fromOffset(190, 42), Position = UDim2.fromOffset(10, 0), Text = "Cash  $0", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center}, moneyBar)
local stackLbl = label({Size = UDim2.fromOffset(190, 42), Position = UDim2.fromOffset(200, 0), Text = "Stack  $0", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center}, moneyBar)

local amountFrame = new("Frame", {Size = UDim2.fromOffset(400, 36), Position = UDim2.fromOffset(20, 118), BackgroundTransparency = 1}, rightPanel)
local amountBox = new("TextBox", {Size = UDim2.fromOffset(180, 36), Position = UDim2.fromOffset(0, 0), BackgroundColor3 = Color3.fromRGB(13, 8, 32), BorderSizePixel = 0, Text = "", PlaceholderText = "Amount", TextColor3 = Color3.new(1, 1, 1), PlaceholderColor3 = Color3.fromRGB(255, 255, 255), FontFace = FONT, TextSize = 16, ClearTextOnFocus = false}, amountFrame)
corner(amountBox, 6)
local depositBtn = new("TextButton", {Size = UDim2.fromOffset(100, 36), Position = UDim2.fromOffset(190, 0), BackgroundColor3 = Color3.fromRGB(0, 170, 80), BorderSizePixel = 0, Text = "إيداع", FontFace = FONT, TextSize = 16, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = false}, amountFrame)
corner(depositBtn, 6)
local withdrawBtn = new("TextButton", {Size = UDim2.fromOffset(100, 36), Position = UDim2.fromOffset(300, 0), BackgroundColor3 = Color3.fromRGB(141, 2, 255), BorderSizePixel = 0, Text = "سحب", FontFace = FONT, TextSize = 16, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = false}, amountFrame)
corner(withdrawBtn, 6)

grid2.Position = UDim2.fromOffset(20, 175)
grid2.Size = UDim2.fromOffset(400, 380)

local function button(text, y)
	local b = new("TextButton", {Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, y), BackgroundColor3 = PURPLE, BorderSizePixel = 0, AutoButtonColor = false, Text = text, FontFace = FONT, TextSize = 17, TextColor3 = Color3.new(1, 1, 1)}, mid)
	corner(b, 7)
	b.MouseEnter:Connect(function() b.BackgroundColor3 = Color3.fromRGB(144, 100, 255) end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = PURPLE end)
	return b
end

local useBtn, giveBtn, closeBtn = button("USE", 20), button("GIVE", 68), button("CLOSE", 116)

local hotHolder = new("Frame", {Size = UDim2.fromOffset(72, 384), Position = UDim2.fromOffset(20, 180), BackgroundTransparency = 1}, mid)
new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, hotHolder)
for i = 1, 5 do
	local s = makeSlot(hotHolder, "hot", 0, i)
	s.frame.Size = UDim2.fromOffset(72, 72)
	s.frame.LayoutOrder = i
	s.frame.BackgroundColor3 = Color3.fromRGB(34, 26, 66)
	hotSlots[i] = s
end

local function info(item)
	if typeof(item) == "table" then
		return item.name, item.texture or "", nil, item.weight or 1
	elseif item:IsA("Tool") then
		return item.Name, item.TextureId, item:FindFirstChild("Handle"), item:GetAttribute("Weight") or 1
	end
	return item:GetAttribute("ToolName") or item.Name, item:GetAttribute("Texture") or "", item, item:GetAttribute("Weight") or 1
end

local function fillViewport(vp, handle)
	vp:ClearAllChildren()
	vp.CurrentCamera = nil
	if not handle or not handle:IsA("BasePart") then return end
	local clone = handle:Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then d:Destroy() end
	end
	clone.Anchored = true
	clone.CFrame = CFrame.new()
	clone.Parent = vp
	local radius = math.max(clone.Size.Magnitude / 2, 0.5)
	local dist = radius / math.sin(math.rad(35)) * 1.1
	local cam = new("Camera", {FieldOfView = 70, CFrame = CFrame.lookAt(Vector3.new(1, 0.45, 1.2).Unit * dist, Vector3.zero)}, vp)
	vp.CurrentCamera = cam
end

local function weightOf(item)
	local _, _, _, w = info(item)
	return w
end

local function owned(t)
	return t and t.Parent ~= nil and (t.Parent == getBackpack() or (player.Character and t.Parent == player.Character))
end

local function allTools()
	local list = {}
	local bp = getBackpack()
	if bp then
		for _, t in ipairs(bp:GetChildren()) do
			if t:IsA("Tool") then
				table.insert(list, t)
			end
		end
	end
	if player.Character then
		for _, t in ipairs(player.Character:GetChildren()) do
			if t:IsA("Tool") then
				table.insert(list, t)
			end
		end
	end
	return list
end

local function inHotbar(t)
	for h = 1, 5 do
		if hotbar[h] == t then return true end
	end
	return false
end

local function inLayout1(t)
	for i = 1, 25 do
		if layout[1][i] == t then return true end
	end
	return false
end

local function isHidden(x)
	local u = hidden[x]
	if u and os.clock() < u then return true end
	hidden[x] = nil
	return false
end

local function sync()
	for i = 1, 25 do
		local t = layout[1][i]
		if t and not owned(t) then
			layout[1][i] = nil
		end
	end
	for h = 1, 5 do
		if hotbar[h] and not owned(hotbar[h]) then hotbar[h] = nil end
	end
	for _, t in ipairs(allTools()) do
		if not inLayout1(t) and not inHotbar(t) and not isHidden(t) then
			if pendingSlot and not layout[1][pendingSlot] then
				layout[1][pendingSlot] = t
				pendingSlot = nil
			else
				for i = 1, 25 do
					if not layout[1][i] then
						layout[1][i] = t
						break
					end
				end
			end
		end
	end
end

local function refreshVault()
	for i = 1, 25 do
		layout[2][i] = nil
	end
	local idx = 1
	for _, data in pairs(vaultItems) do
		if idx > 25 then break end
		layout[2][idx] = data
		idx += 1
	end
end

local function paint(s, item, isSel)
	local has = item ~= nil
	if s.key ~= item then
		s.key = item
		s.icon.Visible, s.vp.Visible, s.txt.Visible = false, false, false
		if has then
			local name, tex, handle = info(item)
			if tex ~= "" then
				s.icon.Image = tex
				s.icon.Visible = true
			elseif handle then
				fillViewport(s.vp, handle)
				s.vp.Visible = true
			else
				s.txt.Text = name
				s.txt.Visible = true
			end
			s.tagLbl.Text = name
		end
	end
	s.bar.Visible = has and s.kind == "grid"
	s.qty.Visible = has and s.kind == "grid"
	s.tag.Visible = has and isSel and s.kind == "grid"
	if s.kind == "grid" then
		s.frame.BackgroundColor3 = isSel and PURPLE or SLOT
		s.stroke.Color = isSel and Color3.fromRGB(154, 116, 255) or STROKE
	else
		local eq = has and typeof(item) ~= "table" and item.Parent == player.Character
		s.stroke.Color = eq and PURPLE or STROKE
		s.stroke.Thickness = eq and 2 or 1
	end
end

function render()
	sync()
	refreshVault()
	for p = 1, 2 do
		local total = 0
		for i = 1, 25 do
			local it = layout[p][i]
			if it then total += weightOf(it) end
			paint(gridSlots[p][i], it, it ~= nil and selected ~= nil and selected[1] == p and selected[2] == i)
		end
		weightUI[p][1].Text = ("%d / %s KG"):format(math.floor(total), "120")
		weightUI[p][2].Size = UDim2.fromScale(math.clamp(total / 120, 0, 1), 1)
	end
	for h = 1, 5 do
		paint(hotSlots[h], hotbar[h], false)
	end

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cash = ls:FindFirstChild("Cash")
		local bank = ls:FindFirstChild("Bank")
		if cash then cashLbl.Text = "Cash  $" .. cash.Value end
		if bank then stackLbl.Text = "Stack  $" .. bank.Value end
	end
end

local function toggleEquip(tool)
	if typeof(tool) == "table" then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (tool and hum and owned(tool)) then return end
	if tool.Parent == char then
		hum:UnequipTools()
	else
		hum:EquipTool(tool)
	end
end

local function mousePos(input)
	return Vector2.new(input.Position.X, input.Position.Y) + GuiSvc:GetGuiInset()
end

local function slotAt(pos)
	for _, r in ipairs(refs) do
		local a, s = r.frame.AbsolutePosition, r.frame.AbsoluteSize
		if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then
			return r
		end
	end
end

local function inside(f, pos)
	local a, s = f.AbsolutePosition, f.AbsoluteSize
	return pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y
end

local function clearFromHotbar(tool)
	for h = 1, 5 do
		if hotbar[h] == tool then hotbar[h] = nil end
	end
end

local function firstEmpty(p)
	for i = 1, 25 do
		if not layout[p][i] then return i end
	end
end

local dragging, ghost
local function getItem(r)
	if r.kind == "grid" then
		return layout[r.p][r.i]
	else
		return hotbar[r.i]
	end
end

for _, r in ipairs(refs) do
	r.frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and r.kind == "hot" then
			hotbar[r.i] = nil
			render()
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local item = getItem(r)
		if r.kind == "grid" then
			selected = {r.p, r.i}
			render()
		end
		if item then
			dragging = {ref = r, item = item, start = mousePos(input), moved = false, source = r}
		end
	end)
end

UIS.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local pos = mousePos(input)
	if not dragging.moved and (pos - dragging.start).Magnitude > 6 then
		dragging.moved = true
		local sz = 72 * uiScale.Scale
		ghost = new("Frame", {Size = UDim2.fromOffset(sz, sz), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PURPLE, BackgroundTransparency = 0.3, ZIndex = 50, BorderSizePixel = 0}, gui)
		corner(ghost, 7)
		local s = dragging.source
		local vis = s.icon.Visible and s.icon or (s.vp.Visible and s.vp) or s.txt
		local c = vis:Clone()
		c.Size = UDim2.fromScale(0.85, 0.7)
		c.Position = UDim2.fromScale(0.075, 0.1)
		c.Visible = true
		c.ZIndex = 51
		c.Parent = ghost
	end
	if ghost then
		ghost.Position = UDim2.fromOffset(pos.X, pos.Y)
	end
end)

UIS.InputEnded:Connect(function(input)
	if not dragging then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local d = dragging
	dragging = nil
	if ghost then ghost:Destroy() ghost = nil end

	local src, item = d.ref, d.item
	if not d.moved then
		if src.kind == "hot" then toggleEquip(item) end
		render()
		return
	end

	local pos = mousePos(input)
	local target = slotAt(pos)
	local zone = nil
	if target and target.kind == "grid" then
		zone = target.p
	elseif not target then
		if inside(rightPanel, pos) then
			zone = 2
		elseif inside(leftPanel, pos) then
			zone = 1
		end
	end

	if src.kind == "grid" and src.p == 1 then
		if target and target.kind == "grid" and target.p == 1 then
			layout[1][src.i], layout[1][target.i] = layout[1][target.i], layout[1][src.i]
			selected = {1, target.i}
		elseif target and target.kind == "hot" then
			local other = hotbar[target.i]
			hotbar[target.i] = item
			layout[1][src.i] = other
			selected = nil
		elseif zone == 2 then
			layout[1][src.i] = nil
			clearFromHotbar(item)
			hidden[item] = os.clock() + 2
			selected = nil
			DepositEv:FireServer(item)
		end
	elseif src.kind == "grid" and src.p == 2 then
		if zone == 1 then
			local id = item.id
			if id then
				pendingSlot = (target and layout[1][target.i] == nil) and target.i or nil
				task.delay(2, function() pendingSlot = nil end)
				layout[2][src.i] = nil
				vaultItems[id] = nil
				hidden[item] = os.clock() + 2
				selected = nil
				WithdrawEv:FireServer(id)
			end
		elseif target and target.kind == "grid" and target.p == 2 then
			layout[2][src.i], layout[2][target.i] = layout[2][target.i], layout[2][src.i]
		end
	elseif src.kind == "hot" then
		if target and target.kind == "hot" then
			hotbar[src.i], hotbar[target.i] = hotbar[target.i], hotbar[src.i]
		elseif zone == 1 then
			local dest = (target and target.kind == "grid") and target.i or firstEmpty(1)
			if dest then
				hotbar[src.i] = layout[1][dest]
				layout[1][dest] = item
				selected = {1, dest}
			end
		elseif zone == 2 then
			hotbar[src.i] = nil
			hidden[item] = os.clock() + 2
			DepositEv:FireServer(item)
		end
	end
	render()
end)

useBtn.Activated:Connect(function()
	if not selected or selected[1] ~= 1 then return end
	local t = layout[1][selected[2]]
	if t then toggleEquip(t) render() end
end)

giveBtn.Activated:Connect(function()
	if not selected or selected[1] ~= 1 then return end
	local t = layout[1][selected[2]]
	if t then GiveEv:FireServer(t) end
end)

depositBtn.Activated:Connect(function()
	local amount = tonumber(amountBox.Text)
	if amount and amount > 0 then
		MoneyDepositEv:FireServer(amount)
		amountBox.Text = ""
	end
end)

withdrawBtn.Activated:Connect(function()
	local amount = tonumber(amountBox.Text)
	if amount and amount > 0 then
		MoneyWithdrawEv:FireServer(amount)
		amountBox.Text = ""
	end
end)

closeBtn.Activated:Connect(function()
	gui.Enabled = false
end)

local function setOpen(v)
	gui.Enabled = v
	if v then render() end
end

VaultSyncEv.OnClientEvent:Connect(function(list)
	vaultItems = {}
	for _, data in ipairs(list) do
		vaultItems[data.id] = data
	end
	if gui.Enabled then render() end
end)

local function watch(container)
	if container then
		container.ChildAdded:Connect(function() if gui.Enabled then render() end end)
		container.ChildRemoved:Connect(function() if gui.Enabled then render() end end)
	end
end

local watchedBackpack
local function watchBackpack()
	local bp = getBackpack()
	if bp and bp ~= watchedBackpack then
		watchedBackpack = bp
		watch(bp)
	end
end

watchBackpack()
player.ChildAdded:Connect(function(c)
	if c:IsA("Backpack") then watchBackpack() end
end)

if player.Character then watch(player.Character) end
player.CharacterAdded:Connect(function(c)
	watch(c)
	watchBackpack()
end)

task.spawn(function()
	while true do
		task.wait(0.3)
		if gui.Enabled then render() end
	end
end)

local function updateMoney()
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cash = ls:FindFirstChild("Cash")
		local bank = ls:FindFirstChild("Bank")
		if cash then cash:GetPropertyChangedSignal("Value"):Connect(function() if gui.Enabled then render() end end) end
		if bank then bank:GetPropertyChangedSignal("Value"):Connect(function() if gui.Enabled then render() end end) end
	end
end

updateMoney()
player.ChildAdded:Connect(function(c)
	if c.Name == "leaderstats" then updateMoney() end
end)

render()
print("[Inventory] UI initialized. Use external button to toggle GUI.")
