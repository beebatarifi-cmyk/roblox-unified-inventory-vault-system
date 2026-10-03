-- ExternalButtonToggle.lua
-- Put this script inside your external button (GuiButton / TextButton / ImageButton)
-- The button will toggle the InventoryUI open/close.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function getInventoryUI()
	for i = 1, 50 do
		local gui = playerGui:FindFirstChild("InventoryUI")
		if gui then
			return gui
		end
		task.wait(0.2)
	end
	return nil
end

local button = script.Parent
if not button:IsA("GuiButton") and not button:IsA("TextButton") then
	warn("[InventoryButton] This script must be placed inside a GuiButton/TextButton/ImageButton.")
	return
end

button.Activated:Connect(function()
	local gui = getInventoryUI()
	if gui then
		gui.Enabled = not gui.Enabled
	end
end)

print("[InventoryButton] Ready. This button toggles InventoryUI.")
