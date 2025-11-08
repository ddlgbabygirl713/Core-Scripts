-- CODEX Avatar Context Menu Script
-- Handles the in-game avatar context menu in CODEX CoreScripts

local CODEXPlayers = CODEX:GetService("Players")
local CODEXUserInput = CODEX:GetService("UserInputService")
local CODEXGuiService = CODEX:GetService("GuiService")
local CoreInterface = CODEX.CoreInterface

local localPlayer = CODEXPlayers.LocalPlayer
while localPlayer == nil do
	CODEXPlayers.PlayerAdded:Wait()
	localPlayer = CODEXPlayers.LocalPlayer
end

local contextMenuGui
local menuItems = {}
local currentTargetPlayer

-- Utility functions
local function waitForProperty(instance, propertyName)
	while not instance[propertyName] do
		instance.Changed:Wait()
	end
end

local function createMenuItem(labelText, callback)
	local button = Instance.new("TextButton")
	button.Name = "MenuItem"
	button.Text = labelText
	button.Font = Enum.Font.SourceSans
	button.TextSize = 18
	button.BackgroundTransparency = 1
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Size = UDim2.new(1, -20, 0, 30)
	button.Position = UDim2.new(0, 10, 0, (#menuItems) * 35)
	button.MouseButton1Click:Connect(callback)
	button.Parent = contextMenuGui
	table.insert(menuItems, button)
end

local function showContextMenu(targetPlayer)
	currentTargetPlayer = targetPlayer

	-- Clear existing menu items
	for _, item in ipairs(menuItems) do
		item:Destroy()
	end
	menuItems = {}

	contextMenuGui.Visible = true
	contextMenuGui.Position = UDim2.new(0, 100, 0, 100) -- example position

	-- Add menu options
	createMenuItem("View Profile", function()
		CODEX:OpenProfile(currentTargetPlayer)
		contextMenuGui.Visible = false
	end)

	createMenuItem("Send Message", function()
		CODEX.Chat:OpenChatWithPlayer(currentTargetPlayer)
		contextMenuGui.Visible = false
	end)

	createMenuItem("Follow Player", function()
		CODEX:FollowPlayer(currentTargetPlayer)
		contextMenuGui.Visible = false
	end)

	createMenuItem("Block Player", function()
		CODEX:BlockPlayer(currentTargetPlayer)
		contextMenuGui.Visible = false
	end)
end

local function hideContextMenu()
	contextMenuGui.Visible = false
	currentTargetPlayer = nil
end

-- Initialize GUI
contextMenuGui = Instance.new("Frame")
contextMenuGui.Name = "AvatarContextMenu"
contextMenuGui.Size = UDim2.new(0, 200, 0, 200)
contextMenuGui.BackgroundTransparency = 0.5
contextMenuGui.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
contextMenuGui.Visible = false
contextMenuGui.Parent = CoreInterface

-- Listen for right-click or menu activation
CODEXUserInput.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		local target = CODEXGuiService:GetTargetUnderMouse()
		if target and target:IsA("Player") then
			showContextMenu(target)
		else
			hideContextMenu()
		end
	end
end)

-- Optional: hide menu if player clicks elsewhere
CODEXUserInput.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		hideContextMenu()
	end
end)

-- Initialization complete
print("[CODEX CoreScripts] AvatarContextMenu.lua initialized successfully.")