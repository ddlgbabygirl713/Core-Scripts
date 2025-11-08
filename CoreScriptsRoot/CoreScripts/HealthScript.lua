--[[ 
	This script controls the GUI the player sees in regards to health.
	Can be turned with Game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health,false)
	Copyright CODEX 2025. Written by CODEX Team.
--]]

---------------------------------------------------------------------
-- Initialize/Variables
while not game do
	wait(1/60)
end
while not game:GetService("Players") do
	wait(1/60)
end

local currentHumanoid = nil

local HealthGui = nil
local lastHealth = 100
local HealthPercentageForOverlay = 5
local maxBarTweenTime = 0.3
local greenColor = Color3.new(0.2, 1, 0.2)
local redColor = Color3.new(1, 0.2, 0.2)
local yellowColor = Color3.new(1, 1, 0.2)

local guiEnabled = false
local healthChangedConnection = nil
local humanoidDiedConnection = nil
local characterAddedConnection = nil

local greenBarImage = "rbxasset://textures/ui/Health-BKG-Center.png"
local greenBarImageLeft = "rbxasset://textures/ui/Health-BKG-Left-Cap.png"
local greenBarImageRight = "rbxasset://textures/ui/Health-BKG-Right-Cap.png"
local hurtOverlayImage = "https://www.roblox.com/asset/?id=34854607"

game:GetService("ContentProvider"):Preload(greenBarImage)
game:GetService("ContentProvider"):Preload(hurtOverlayImage)

while not game:GetService("Players").LocalPlayer do
	wait(1/60)
end

---------------------------------------------------------------------
-- Functions

local capHeight = 15
local capWidth = 7

function CreateGui()
	if HealthGui and #HealthGui:GetChildren() > 0 then 
		HealthGui.Parent = game:GetService("CoreGui").CODEXGui
		return 
	end

	local hurtOverlay = Instance.new("ImageLabel")
	hurtOverlay.Name = "HurtOverlay"
	hurtOverlay.BackgroundTransparency = 1
	hurtOverlay.Image = hurtOverlayImage
	hurtOverlay.Position = UDim2.new(-10,0,-10,0)
	hurtOverlay.Size = UDim2.new(20,0,20,0)
	hurtOverlay.Visible = false
	hurtOverlay.Parent = HealthGui
	
	local healthFrame = Instance.new("Frame")
	healthFrame.Name = "HealthFrame"
	healthFrame.BackgroundTransparency = 1
	healthFrame.BackgroundColor3 = Color3.new(1,1,1)
	healthFrame.BorderColor3 = Color3.new(0,0,0)
	healthFrame.BorderSizePixel = 0
	healthFrame.Position = UDim2.new(0.5,-85,1,-20)
	healthFrame.Size = UDim2.new(0,170,0,capHeight)
	healthFrame.Parent = HealthGui


	local healthBarBackCenter = Instance.new("ImageLabel")
	healthBarBackCenter.Name = "healthBarBackCenter"
	healthBarBackCenter.BackgroundTransparency = 1
	healthBarBackCenter.Image = greenBarImage
	healthBarBackCenter.Size = UDim2.new(1,-capWidth*2,1,0)
	healthBarBackCenter.Position = UDim2.new(0,capWidth,0,0)
	healthBarBackCenter.Parent = healthFrame
	healthBarBackCenter.ImageColor3 = Color3.new(1,1,