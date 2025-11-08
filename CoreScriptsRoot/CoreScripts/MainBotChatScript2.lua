-- MainBotChatScript2.lua
-- CODEX CoreScripts: Player/NPC dialog controller (rebranded from Roblox -> CODEX)
-- Preserves original dialog flow: chat notification, choice presentation, timeouts, walk-away handling.

local PURPOSE_DATA = {
	[Enum.DialogPurpose.Quest] = {
		"codexasset://textures/ui/dialog_purpose_quest.png",
		Vector2.new(10, 34)
	},
	[Enum.DialogPurpose.Help] = {
		"codexasset://textures/ui/dialog_purpose_help.png",
		Vector2.new(20, 35)
	},
	[Enum.DialogPurpose.Shop] = {
		"codexasset://textures/ui/dialog_purpose_shop.png",
		Vector2.new(22, 43)
	},
}

local TEXT_HEIGHT = 24 -- Pixel height of one row
local FONT_SIZE = Enum.FontSize.Size24
local BAR_THICKNESS = 6
local STYLE_PADDING = 17
local CHOICE_PADDING = 6 * 2 -- (Added to vertical height)
local PROMPT_SIZE = Vector2.new(80, 90)
local FRAME_WIDTH = 350

local WIDTH_BONUS = (STYLE_PADDING * 2) - BAR_THICKNESS
local XPOS_OFFSET = -(STYLE_PADDING - BAR_THICKNESS)

-- CODEX service proxies (rebranded)
local CODEX = _G.CODEX or game -- If you're running in a test environment, fall back to `game`
local playerService = CODEX:GetService("Players")
local contextActionService = CODEX:GetService("ContextActionService")
local guiService = CODEX:GetService("GuiService")
local UserInputService = CODEX:GetService("UserInputService")

local YPOS_OFFSET = -math.floor(STYLE_PADDING / 2)
local usingGamepad = false

local FlagHasReportedPlace = false

local localPlayer = playerService.LocalPlayer
if not localPlayer then
	localPlayer = playerService.PlayerAdded:Wait()
end

-- Track input type (gamepad vs others)
local function setUsingGamepad(input, processed)
	if input and (input.UserInputType == Enum.UserInputType.Gamepad1
		or input.UserInputType == Enum.UserInputType.Gamepad2
		or input.UserInputType == Enum.UserInputType.Gamepad3
		or input.UserInputType == Enum.UserInputType.Gamepad4) then
		usingGamepad = true
	else
		usingGamepad = false
	end
end

UserInputService.InputBegan:Connect(setUsingGamepad)
UserInputService.InputChanged:Connect(setUsingGamepad)

-- Feature flag retrieving in CODEX settings API (kept pcall for safety)
local FFlagCoreScriptTranslateGameText2 = pcall(function() return settings():GetFFlag("CoreScriptTranslateGameText2") end) and settings():GetFFlag("CoreScriptTranslateGameText2") or false

local function waitForProperty(instance, name)
	while not instance[name] do
		instance.Changed:Wait()
	end
end

local goodbyeChoiceActiveFlagSuccess, goodbyeChoiceActiveFlagValue = pcall(function()
	return settings():GetFFlag("GoodbyeChoiceActiveProperty")
end)
local goodbyeChoiceActiveFlag = (goodbyeChoiceActiveFlagSuccess and goodbyeChoiceActiveFlagValue)

-- UI / state locals
local mainFrame
local choices = {}
local lastChoice
local choiceMap = {}
local currentConversationDialog
local currentConversationPartner
local currentAbortDialogScript

local coroutineMap = {}
local currentDialogTimeoutCoroutine = nil

local tooFarAwayMessage =           "You are too far away to chat!"
local tooFarAwaySize = 300
local characterWanderedOffMessage = "Chat ended because you walked away"
local characterWanderedOffSize = 350
local conversationTimedOut =        "Chat ended because you didn't reply"
local conversationTimedOutSize = 350

local CoreInterface = CODEX:GetService("CoreInterface")
local CODEXGui = CoreInterface:WaitForChild("CODEXGui")
local CODEXReplicatedStorage = CODEX:GetService('ReplicatedStorage')
local setDialogInUseEvent = CODEXReplicatedStorage:WaitForChild("SetDialogInUse", 86400)

local player
local screenGui
local chatNotificationGui
local messageDialog
local timeoutScript
local reenableDialogScript
local dialogMap = {}
local dialogConnections = {}
local touchControlGui = nil

local gui = nil

-- Modules (assumed to exist in CODEXGui/Modules for parity)
local TenFootInterface = require(CODEXGui:WaitForChild("Modules"):WaitForChild("TenFootInterface"))
local isTenFootInterface = TenFootInterface:IsEnabled()
local utility = require(CODEXGui.Modules.Settings.Utility)
local GameTranslator = require(CODEXGui.Modules.GameTranslator)
local isSmallTouchScreen = utility:IsSmallTouchScreen()

if isTenFootInterface then
	FONT_SIZE = Enum.FontSize.Size36
	TEXT_HEIGHT = 36
	FRAME_WIDTH = 500
elseif isSmallTouchScreen then
	FONT_SIZE = Enum.FontSize.Size14
	TEXT_HEIGHT = 14
	FRAME_WIDTH = 250
end

if CODEXGui:FindFirstChild("ControlFrame") then
	gui = CODEXGui.ControlFrame
else
	gui = CODEXGui
end

local touchEnabled = UserInputService.TouchEnabled

-- Determine if dialog is a multi-player dialog (safe pcall)
local function isDialogMultiplePlayers(dialog)
	local success, value = pcall(function() return dialog.BehaviorType == Enum.DialogBehaviorType.MultiplePlayers end)
	return success and value or false
end

local function currentTone()
	if currentConversationDialog then
		return currentConversationDialog.Tone
	else
		return Enum.DialogTone.Neutral
	end
end

-- Create a CODEX-branded chat notification billboard template
local function createChatNotificationGui()
	chatNotificationGui = Instance.new("BillboardGui")
	chatNotificationGui.Name = "ChatNotificationGui"
	chatNotificationGui.ExtentsOffset = Vector3.new(0, 1, 0)
	chatNotificationGui.Size = UDim2.new(PROMPT_SIZE.X / 31.5, 0, PROMPT_SIZE.Y / 31.5, 0)
	chatNotificationGui.SizeOffset = Vector2.new(0, 0)
	chatNotificationGui.StudsOffset = Vector3.new(0, 3.7, 0)
	chatNotificationGui.Enabled = true
	chatNotificationGui.RobloxLocked = true -- we keep property name for parity; treat as "locked" in CODEX
	chatNotificationGui.Active = true

	local button = Instance.new("ImageButton")
	button.Name = "Background"
	button.Active = false
	button.BackgroundTransparency = 1
	button.Position = UDim2.new(0, 0, 0, 0)
	button.Size = UDim2.new(1, 0, 1, 0)
	button.Image = ""
	button.Parent = chatNotificationGui

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Position = UDim2.new(0, 0, 0, 0)
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.Image = ""
	icon.BackgroundTransparency = 1
	icon.Parent = button

	local activationButton = Instance.new("ImageLabel")
	activationButton.Name = "ActivationButton"
	activationButton.Position = UDim2.new(-0.3, 0, -0.4, 0)
	activationButton.Size = UDim2.new(.8, 0, .8 * (PROMPT_SIZE.X / PROMPT_SIZE.Y), 0)
	activationButton.Image = "codexasset://textures/ui/Settings/Help/XButtonDark.png"
	activationButton.BackgroundTransparency = 1
	activationButton.Visible = false
	activationButton.Parent = button
end

local function getChatColor(tone)
	if tone == Enum.DialogTone.Neutral then
		return Enum.ChatColor.Blue
	elseif tone == Enum.DialogTone.Friendly then
		return Enum.ChatColor.Green
	elseif tone == Enum.DialogTone.Enemy then
		return Enum.ChatColor.Red
	end
end

local function styleChoices()
	for _, obj in pairs(choices) do
		obj.BackgroundTransparency = 1
	end
	if lastChoice then lastChoice.BackgroundTransparency = 1 end
end

local function styleMainFrame(tone)
	if tone == Enum.DialogTone.Neutral then
		mainFrame.Style = Enum.FrameStyle.ChatBlue
	elseif tone == Enum.DialogTone.Friendly then
		mainFrame.Style = Enum.FrameStyle.ChatGreen
	elseif tone == Enum.DialogTone.Enemy then
		mainFrame.Style = Enum.FrameStyle.ChatRed
	end

	styleChoices()
end

local function setChatNotificationTone(guiObj, purpose, tone)
	if tone == Enum.DialogTone.Neutral then
		guiObj.Background.Image = "codexasset://textures/ui/chatBubble_blue_notify_bkg.png"
	elseif tone == Enum.DialogTone.Friendly then
		guiObj.Background.Image = "codexasset://textures/ui/chatBubble_green_notify_bkg.png"
	elseif tone == Enum.DialogTone.Enemy then
		guiObj.Background.Image = "codexasset://textures/ui/chatBubble_red_notify_bkg.png"
	end

	local newIcon, size = unpack(PURPOSE_DATA[purpose])
	local relativeSize = size / PROMPT_SIZE
	guiObj.Background.Icon.Size = UDim2.new(relativeSize.X, 0, relativeSize.Y, 0)
	guiObj.Background.Icon.Position = UDim2.new(0.5 - (relativeSize.X / 2), 0, 0.4 - (relativeSize.Y / 2), 0)
	guiObj.Background.Icon.Image = newIcon
end

local function createMessageDialog()
	messageDialog = Instance.new("Frame");
	messageDialog.Name = "DialogScriptMessage"
	messageDialog.Style = Enum.FrameStyle.Custom
	messageDialog.BackgroundTransparency = 0.5
	messageDialog.BackgroundColor3 = Color3.new(31 / 255, 31 / 255, 31 / 255)
	messageDialog.Visible = false
	messageDialog.RobloxLocked = true

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Position = UDim2.new(0, 0, 0, -1)
	text.Size = UDim2.new(1, 0, 1, 0)
	text.FontSize = Enum.FontSize.Size14
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Parent = messageDialog
end

local function showMessage(msg, size)
	messageDialog.Text.Text = msg
	messageDialog.Size = UDim2.new(0, size, 0, 40)
	messageDialog.Position = UDim2.new(0.5, -size / 2, 0.5, -40)
	messageDialog.Visible = true
	task.wait(2)
	messageDialog.Visible = false
end

local function variableDelay(str)
	local length = math.min(string.len(str), 100)
	task.wait(0.75 + ((length / 75) * 1.5))
end

local function resetColor(frame)
	frame.BackgroundTransparency = 1
end

local function endDialog()
	if currentDialogTimeoutCoroutine then
		coroutineMap[currentDialogTimeoutCoroutine] = false
		currentDialogTimeoutCoroutine = nil
	end

	local dialog = currentConversationDialog
	currentConversationDialog = nil
	if dialog and dialog.InUse then
		-- Set InUse false on server after 5 seconds (pcall for CODEX network safety)
		pcall(function() setDialogInUseEvent:FireServer(dialog, false, 5) end)
		delay(5, function()
			if dialog then dialog.InUse = false end
		end)
	end

	for d, guiObj in pairs(dialogMap) do
		if d and guiObj then
			guiObj.Enabled = not d.InUse
		end
	end

	contextActionService:UnbindCoreAction("Nothing")
	currentConversationPartner = nil

	if touchControlGui then
		touchControlGui.Visible = true
	end
end

local function wanderDialog()
	if mainFrame then mainFrame.Visible = false end
	endDialog()
	showMessage(characterWanderedOffMessage, characterWanderedOffSize)
end

local function timeoutDialog()
	if mainFrame then mainFrame.Visible = false end
	endDialog()
	showMessage(conversationTimedOut, conversationTimedOutSize)
end

local function normalEndDialog()
	endDialog()
end

local function sanitizeMessage(msg)
	if string.len(msg) == 0 then
		return "..."
	else
		return msg
	end
end

-- Chat function respects multiple players (reuses Game Chat API semantics)
local function chatFunc(dialog, ...)
	if isDialogMultiplePlayers(dialog) then
		CODEX:GetService("Chat"):ChatLocal(...)
	else
		CODEX:GetService("Chat"):Chat(...)
	end
end

local function selectChoice(choice)
	renewKillswitch(currentConversationDialog)

	if mainFrame then mainFrame.Visible = false end
	if choice == lastChoice then
		chatFunc(currentConversationDialog, localPlayer.Character, lastChoice.UserPrompt.Text, getChatColor(currentTone()))
		normalEndDialog()
	else
		local dialogChoice = choiceMap[choice]

		chatFunc(currentConversationDialog, localPlayer.Character, sanitizeMessage(dialogChoice.UserDialog), getChatColor(currentTone()))
		task.wait(1)
		-- signal the server that the player selected a choice
		local ok, err = pcall(function()
			if currentConversationDialog then
				currentConversationDialog:SignalDialogChoiceSelected(localPlayer, dialogChoice)
			end
		end)
		if not ok then warn("SignalDialogChoiceSelected failed:", err) end

		chatFunc(currentConversationDialog, currentConversationPartner, sanitizeMessage(dialogChoice.ResponseDialog), getChatColor(currentTone()))
		variableDelay(dialogChoice.ResponseDialog)
		presentDialogChoices(currentConversationPartner, dialogChoice:GetChildren(), dialogChoice)
	end
end

local function newChoice()
	local dummyFrame = Instance.new("Frame")
	dummyFrame.Visible = false

	local frame = Instance.new("TextButton")
	frame.BackgroundColor3 = Color3.new(227 / 255, 227 / 255, 227 / 255)
	frame.BackgroundTransparency = 1
	frame.AutoButtonColor = false
	frame.BorderSizePixel = 0
	frame.Text = ""
	frame.MouseEnter:Connect(function() frame.BackgroundTransparency = 0 end)
	frame.MouseLeave:Connect(function() frame.BackgroundTransparency = 1 end)
	frame.SelectionImageObject = dummyFrame
	frame.MouseButton1Click:Connect(function() selectChoice(frame) end)
	frame.RobloxLocked = true

	local prompt = Instance.new("TextLabel")
	prompt.Name = "UserPrompt"
	prompt.BackgroundTransparency = 1
	prompt.Font = Enum.Font.SourceSans
	prompt.FontSize = FONT_SIZE
	prompt.Position = UDim2.new(0, 40, 0, 0)
	prompt.Size = UDim2.new(1, -32 - 40, 1, 0)
	prompt.TextXAlignment = Enum.TextXAlignment.Left
	prompt.TextYAlignment = Enum.TextYAlignment.Center
	prompt.TextWrap = true
	prompt.Parent = frame

	local selectionButton = Instance.new("ImageLabel")
	selectionButton.Name = "CODEXchatDialogSelectionButton"
	selectionButton.Position = UDim2.new(0, 0, 0.5, -33 / 2)
	selectionButton.Size = UDim2.new(0, 33, 0, 33)
	selectionButton.Image = "codexasset://textures/ui/Settings/Help/AButtonLightSmall.png"
	selectionButton.BackgroundTransparency = 1
	selectionButton.Visible = false
	selectionButton.Parent = frame

	return frame
end

function initialize(parent)
	choices[1] = newChoice()
	choices[2] = newChoice()
	choices[3] = newChoice()
	choices[4] = newChoice()

	lastChoice = newChoice()
	lastChoice.UserPrompt.Text = "Goodbye!"
	lastChoice.Size = UDim2.new(1, WIDTH_BONUS, 0, TEXT_HEIGHT + CHOICE_PADDING)

	mainFrame = Instance.new("Frame")
	mainFrame.Name = "UserDialogArea"
	mainFrame.Size = UDim2.new(0, FRAME_WIDTH, 0, 200)
	mainFrame.Style = Enum.FrameStyle.ChatBlue
	mainFrame.Visible = false

	for n, obj in pairs(choices) do
		obj.RobloxLocked = true
		obj.Parent = mainFrame
	end

	lastChoice.RobloxLocked = true
	lastChoice.Parent = mainFrame

	mainFrame.RobloxLocked = true
	mainFrame.Parent = parent
end

function presentDialogChoices(talkingPart, dialogChoices, parentDialog)
	if not currentConversationDialog then return end

	currentConversationPartner = talkingPart
	local sortedDialogChoices = {}
	for n, obj in pairs(dialogChoices) do
		if obj:IsA("DialogChoice") then
			table.insert(sortedDialogChoices, obj)
		end
	end
	table.sort(sortedDialogChoices, function(a, b) return a.Name < b.Name end)

	if #sortedDialogChoices == 0 then
		normalEndDialog()
		return
	end

	local pos = 1
	local yPosition = 0
	choiceMap = {}
	for n, obj in pairs(choices) do obj.Visible = false end

	for n, obj in pairs(sortedDialogChoices) do
		if pos <= #choices then
			choices[pos].Size = UDim2.new(1, WIDTH_BONUS, 0, TEXT_HEIGHT * 3)
			if FFlagCoreScriptTranslateGameText2 then
				GameTranslator:TranslateAndRegister(choices[pos].UserPrompt, obj, obj.UserDialog)
			else
				choices[pos].UserPrompt.Text = GameTranslator:TranslateGameText(obj, obj.UserDialog)
			end
			local height = (math.ceil(choices[pos].UserPrompt.TextBounds.Y / TEXT_HEIGHT) * TEXT_HEIGHT) + CHOICE_PADDING

			choices[pos].Position = UDim2.new(0, XPOS_OFFSET, 0, YPOS_OFFSET + yPosition)
			choices[pos].Size = UDim2.new(1, WIDTH_BONUS, 0, height)
			choices[pos].Visible = true

			choiceMap[choices[pos]] = obj

			yPosition = yPosition + height + 1 -- The +1 prevents highlight overlap
			pos = pos + 1
		end
	end

	lastChoice.Size = UDim2.new(1, WIDTH_BONUS, 0, TEXT_HEIGHT * 3)
	lastChoice.UserPrompt.Text = parentDialog.GoodbyeDialog == "" and "Goodbye!" or parentDialog.GoodbyeDialog
	local height = (math.ceil(lastChoice.UserPrompt.TextBounds.Y / TEXT_HEIGHT) * TEXT_HEIGHT) + CHOICE_PADDING
	lastChoice.Size = UDim2.new(1, WIDTH_BONUS, 0, height)
	lastChoice.Position = UDim2.new(0, XPOS_OFFSET, 0, YPOS_OFFSET + yPosition)
	lastChoice.Visible = true

	if goodbyeChoiceActiveFlag and not parentDialog.GoodbyeChoiceActive then
		lastChoice.Visible = false
		mainFrame.Size = UDim2.new(0, FRAME_WIDTH, 0, yPosition + (STYLE_PADDING * 2) + (YPOS_OFFSET * 2))
	else
		mainFrame.Size = UDim2.new(0, FRAME_WIDTH, 0, yPosition + lastChoice.AbsoluteSize.Y + (STYLE_PADDING * 2) + (YPOS_OFFSET * 2))
	end

	mainFrame.Position = UDim2.new(0, 20, 1.0, -mainFrame.Size.Y.Offset - 20)
	if isSmallTouchScreen then
		local touchScreenGui = localPlayer.PlayerGui:FindFirstChild("TouchGui")
		if touchScreenGui then
			touchControlGui = touchScreenGui:FindFirstChild("TouchControlFrame")
			if touchControlGui then
				touchControlGui.Visible = false
			end
		end
		mainFrame.Position = UDim2.new(0, 10, 1.0, -mainFrame.Size.Y.Offset)
	end
	styleMainFrame(currentTone())
	mainFrame.Visible = true

	if usingGamepad then
		CODEX:GetService("GuiService").SelectedCoreObject = choices[1]
	end
end

function doDialog(dialog)
	if dialog.InitialPrompt == "" then
		warn("Can't start a dialog with an empty InitialPrompt")
		return
	end

	local isMultiplePlayers = isDialogMultiplePlayers(dialog)

	if dialog.InUse and not isMultiplePlayers then
		return
	else
		currentConversationDialog = dialog
		dialog.InUse = true
		-- bind a no-op core action to reserve gamepad input while dialog runs
		contextActionService:BindCoreAction("Nothing", function() end, false,
			Enum.UserInputType.Gamepad1, Enum.UserInputType.Gamepad2, Enum.UserInputType.Gamepad3, Enum.UserInputType.Gamepad4)
		-- Immediately set InUse true on the server (pcall safety)
		pcall(function() setDialogInUseEvent:FireServer(dialog, true, 0) end)
	end
	chatFunc(dialog, dialog.Parent, dialog.InitialPrompt, getChatColor(dialog.Tone))
	variableDelay(dialog.InitialPrompt)

	presentDialogChoices(dialog.Parent, dialog:GetChildren(), dialog)
end

function renewKillswitch(dialog)
	if currentDialogTimeoutCoroutine then
		coroutineMap[currentDialogTimeoutCoroutine] = false
		currentDialogTimeoutCoroutine = nil
	end

	currentDialogTimeoutCoroutine = coroutine.create(function(thisCoroutine)
		task.wait(15)
		if thisCoroutine ~= nil then
			if coroutineMap[thisCoroutine] == nil then
				pcall(function() setDialogInUseEvent:FireServer(dialog, false, 0) end)
				if dialog then dialog.InUse = false end
			end
			coroutineMap[thisCoroutine] = nil
		end
	end)
	coroutine.resume(currentDialogTimeoutCoroutine, currentDialogTimeoutCoroutine)
end

function checkForLeaveArea()
	while currentConversationDialog do
		if currentConversationDialog.Parent and (localPlayer:DistanceFromCharacter(currentConversationDialog.Parent.Position) >= currentConversationDialog.ConversationDistance) then
			wanderDialog()
		end
		task.wait(1)
	end
end

function startDialog(dialog)
	if dialog.Parent and dialog.Parent:IsA("BasePart") then
		pcall(function()
			-- CODEX analytics event
			if CODEX.Analytics then
				CODEX.Analytics:Report("Dialogue", "Old Dialogue", "Conversation Initiated")
			end
		end)

		if localPlayer:DistanceFromCharacter(dialog.Parent.Position) >= dialog.ConversationDistance then
			showMessage(tooFarAwayMessage, tooFarAwaySize)
			return
		end

		for d, guiObj in pairs(dialogMap) do
			if d and guiObj then
				guiObj.Enabled = false
			end
		end

		renewKillswitch(dialog)
		delay(1, checkForLeaveArea)
		doDialog(dialog)
	end
end

function removeDialog(dialog)
	if dialogMap[dialog] then
		dialogMap[dialog]:Destroy()
		dialogMap[dialog] = nil
	end
	if dialogConnections[dialog] then
		dialogConnections[dialog]:Disconnect()
		dialogConnections[dialog] = nil
	end
end

function addDialog(dialog)
	if dialog.Parent then
		if dialog.Parent:IsA("BasePart") and dialog:IsDescendantOf(CODEX.Workspace) then
			FlagHasReportedPlace = true
			pcall(function()
				-- CODEX place usage analytics
				if CODEX.Analytics then
					CODEX.Analytics:Report("Dialogue", "Old Dialogue", "Used In Place", nil, CODEX.PlaceId)
				end
			end)

			local chatGui = chatNotificationGui:Clone()
			chatGui.Adornee = dialog.Parent
			chatGui.RobloxLocked = true
			chatGui.Enabled = not dialog.InUse or isDialogMultiplePlayers(dialog)
			chatGui.Parent = CoreInterface

			chatGui.Background.MouseButton1Click:Connect(function()
				startDialog(dialog)
			end)
			setChatNotificationTone(chatGui, dialog.Purpose, dialog.Tone)

			dialogMap[dialog] = chatGui

			dialogConnections[dialog] = dial
dialogConnections[dialog] = dialog:GetPropertyChangedSignal("InUse"):Connect(function()
				if dialog.InUse then
					chatGui.Enabled = false
				else
					chatGui.Enabled = true
				end
			end)

			dialog.AncestryChanged:Connect(function(_, parent)
				if not parent then
					removeDialog(dialog)
				end
			end)
		end
	end
end

-- Connect all existing Dialogs
for _, dialog in pairs(CODEX.Workspace:GetDescendants()) do
	if dialog:IsA("Dialog") then
		addDialog(dialog)
	end
end

-- Listen for new Dialogs appearing in workspace
CODEX.Workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Dialog") then
		addDialog(instance)
	end
end)

-- Cleanup listener
CODEX.Workspace.DescendantRemoving:Connect(function(instance)
	if instance:IsA("Dialog") then
		removeDialog(instance)
	end
end)

-- Final CODEX CoreScript handshake
if CODEX.Analytics then
	CODEX.Analytics:Report("Dialogue", "CoreScript Initialized", "MainBotChatScript2 Active", nil, CODEX.PlaceId)
end

print("[CODEX CoreScripts] MainBotChatScript2.lua initialized successfully.")