-- InventoryServer.lua
-- Place this script inside ServerScriptService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PICKUP_RANGE = 9
local GIVE_RANGE = 5
local DROP_LIFETIME = 600
local MAX_WEIGHT = 120

local remotes = ReplicatedStorage:FindFirstChild("InventoryRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "InventoryRemotes"
	remotes.Parent = ReplicatedStorage
end

local function mk(name)
	local r = remotes:FindFirstChild(name)
	if r then return r end
	r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local DropEv = mk("Drop")
local PickupEv = mk("Pickup")
local GiveEv = mk("Give")
local NotifyEv = mk("Notify")
local DepositEv = mk("Deposit")
local WithdrawEv = mk("Withdraw")
local VaultSyncEv = mk("VaultSync")
local MoneyDepositEv = mk("MoneyDeposit")
local MoneyWithdrawEv = mk("MoneyWithdraw")

local dropsWorld = workspace:FindFirstChild("DroppedItems")
if not dropsWorld then
	dropsWorld = Instance.new("Folder")
	dropsWorld.Name = "DroppedItems"
	dropsWorld.Parent = workspace
end

local dropsStore = ServerStorage:FindFirstChild("DroppedTools")
if not dropsStore then
	dropsStore = Instance.new("Folder")
	dropsStore.Name = "DroppedTools"
	dropsStore.Parent = ServerStorage
end

local vaultsFolder = ServerStorage:FindFirstChild("PlayerVaults")
if not vaultsFolder then
	vaultsFolder = Instance.new("Folder")
	vaultsFolder.Name = "PlayerVaults"
	vaultsFolder.Parent = ServerStorage
end

local stored = {}
local nextId = 0
local vaultData = {}
local vaultNextId = {}

local lastAct = {}
local function throttled(plr)
	local now = os.clock()
	if lastAct[plr] and now - lastAct[plr] < 0.2 then
		return true
	end
	lastAct[plr] = now
	return false
end

Players.PlayerRemoving:Connect(function(plr)
	lastAct[plr] = nil
	vaultData[plr] = nil
	vaultNextId[plr] = nil
end)

local function charParts(plr)
	local c = plr.Character
	if not c then return end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hrp and hum and hum.Health > 0 then
		return hrp, hum
	end
end

local function ownsTool(plr, tool)
	return typeof(tool) == "Instance" and tool:IsA("Tool") and (tool.Parent == plr.Backpack or tool.Parent == plr.Character)
end

local function getWeight(tool)
	return tool:GetAttribute("Weight") or 1
end

local function getVaultFolder(plr)
	local folder = vaultsFolder:FindFirstChild(tostring(plr.UserId))
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = tostring(plr.UserId)
		folder.Parent = vaultsFolder
	end
	return folder
end

local function calcVaultWeight(plr)
	local total = 0
	if vaultData[plr] then
		for _, tool in pairs(vaultData[plr]) do
			total += getWeight(tool)
		end
	end
	return total
end

local function sendVault(plr)
	local list = {}
	if vaultData[plr] then
		for id, tool in pairs(vaultData[plr]) do
			table.insert(list, {
				id = id,
				name = tool.Name,
				texture = tool.TextureId,
				weight = getWeight(tool)
			})
		end
	end
	VaultSyncEv:FireClient(plr, list)
end

local function ensureMoney(plr)
	local ls = plr:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = plr
	end

	local cash = ls:FindFirstChild("Cash")
	if not cash then
		cash = Instance.new("IntValue")
		cash.Name = "Cash"
		cash.Value = 10000
		cash.Parent = ls
	end

	local bank = ls:FindFirstChild("Bank")
	if not bank then
		bank = Instance.new("IntValue")
		bank.Name = "Bank"
		bank.Value = 0
		bank.Parent = ls
	end

	return cash, bank
end

local function makeDisplay(tool, id, cf)
	local handle = tool:FindFirstChild("Handle")
	local part
	if handle and handle:IsA("BasePart") then
		part = handle:Clone()
	end

	if part then
		for _, d in ipairs(part:GetDescendants()) do
			if d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				d:Destroy()
			end
		end
	else
		part = Instance.new("Part")
		part.Size = Vector3.new(1.4, 1.4, 1.4)
		part.Color = Color3.fromRGB(123, 75, 245)
		part.Material = Enum.Material.SmoothPlastic
	end

	part.Name = "Drop_" .. id
	part.Anchored = false
	part.CanCollide = true
	part.CanTouch = false
	part.CFrame = cf
	part:SetAttribute("DropId", id)
	part:SetAttribute("ToolName", tool.Name)
	part:SetAttribute("Texture", tool.TextureId)
	part:SetAttribute("Weight", getWeight(tool))
	part.Parent = dropsWorld
	return part
end

DropEv.OnServerEvent:Connect(function(plr, tool)
	if throttled(plr) or not ownsTool(plr, tool) then return end
	local hrp, hum = charParts(plr)
	if not hrp then return end

	nextId += 1
	local id = tostring(nextId)
	hum:UnequipTools()

	local part = makeDisplay(tool, id, hrp.CFrame * CFrame.new(0, 0.5, -3.5))
	tool.Parent = dropsStore
	stored[id] = {tool = tool, part = part}

	if DROP_LIFETIME > 0 then
		task.delay(DROP_LIFETIME, function()
			local item = stored[id]
			if item then
				stored[id] = nil
				item.part:Destroy()
				item.tool:Destroy()
			end
		end)
	end
end)

PickupEv.OnServerEvent:Connect(function(plr, id)
	if throttled(plr) or typeof(id) ~= "string" then return end
	local item = stored[id]
	if not item then return end
	local hrp = charParts(plr)
	if not hrp then return end
	if (item.part.Position - hrp.Position).Magnitude > PICKUP_RANGE then return end

	stored[id] = nil
	item.part:Destroy()
	item.tool.Parent = plr.Backpack
end)

GiveEv.OnServerEvent:Connect(function(plr, tool)
	if throttled(plr) or not ownsTool(plr, tool) then return end
	local hrp, hum = charParts(plr)
	if not hrp then return end

	local best, bestDist
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= plr then
			local oh = charParts(other)
			if oh then
				local d = (oh.Position - hrp.Position).Magnitude
				if d <= GIVE_RANGE and (not bestDist or d < bestDist) then
					best = other
					bestDist = d
				end
			end
		end
	end

	if not best then
		NotifyEv:FireClient(plr, "ما في لاعب قريب")
		return
	end

	hum:UnequipTools()
	tool.Parent = best.Backpack
	NotifyEv:FireClient(plr, "أعطيت " .. tool.Name .. " لـ " .. best.DisplayName)
	NotifyEv:FireClient(best, plr.DisplayName .. " أعطاك " .. tool.Name)
end)

DepositEv.OnServerEvent:Connect(function(plr, tool)
	if throttled(plr) or not ownsTool(plr, tool) then return end
	local w = getWeight(tool)
	if calcVaultWeight(plr) + w > MAX_WEIGHT then
		NotifyEv:FireClient(plr, "الخزنة ممتلئة")
		return
	end
	local _, hum = charParts(plr)
	if hum then
		hum:UnequipTools()
	end

	vaultData[plr] = vaultData[plr] or {}
	vaultNextId[plr] = (vaultNextId[plr] or 0) + 1
	local id = tostring(vaultNextId[plr])
	tool.Parent = getVaultFolder(plr)
	vaultData[plr][id] = tool
	NotifyEv:FireClient(plr, "تم إيداع " .. tool.Name .. " في الخزنة")
	sendVault(plr)
end)

WithdrawEv.OnServerEvent:Connect(function(plr, id)
	if throttled(plr) or typeof(id) ~= "string" then return end
	local data = vaultData[plr]
	if not data or not data[id] then return end
	local tool = data[id]
	data[id] = nil
	tool.Parent = plr.Backpack
	NotifyEv:FireClient(plr, "تم سحب " .. tool.Name .. " من الخزنة")
	sendVault(plr)
end)

MoneyDepositEv.OnServerEvent:Connect(function(plr, amount)
	if throttled(plr) or typeof(amount) ~= "number" or amount <= 0 then return end
	local cash, bank = ensureMoney(plr)
	amount = math.floor(amount)
	if cash.Value < amount then
		NotifyEv:FireClient(plr, "ما عندك فلوس كافية")
		return
	end
	cash.Value -= amount
	bank.Value += amount
	NotifyEv:FireClient(plr, "تم إيداع $" .. amount)
end)

MoneyWithdrawEv.OnServerEvent:Connect(function(plr, amount)
	if throttled(plr) or typeof(amount) ~= "number" or amount <= 0 then return end
	local cash, bank = ensureMoney(plr)
	amount = math.floor(amount)
	if bank.Value < amount then
		NotifyEv:FireClient(plr, "ما في فلوس كافية في الخزنة")
		return
	end
	bank.Value -= amount
	cash.Value += amount
	NotifyEv:FireClient(plr, "تم سحب $" .. amount)
end)

Players.PlayerAdded:Connect(function(plr)
	ensureMoney(plr)
	vaultData[plr] = vaultData[plr] or {}
	vaultNextId[plr] = vaultNextId[plr] or 0
	task.wait(0.5)
	sendVault(plr)
end)

for _, plr in ipairs(Players:GetPlayers()) do
	ensureMoney(plr)
	vaultData[plr] = vaultData[plr] or {}
	vaultNextId[plr] = vaultNextId[plr] or 0
	sendVault(plr)
end

print("[Inventory] Server initialized.")
