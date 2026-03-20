--[[
	LocalScript: Draggable teleport menu GUI for the local player.
	Features:
	- Draggable open button and main menu with screen clamping
	- Save / teleport to a local position
	- Client-side ESP marker + line for the saved location
	- Expandable settings panel with live color pickers
	- Per-place config save/load helpers with graceful fallback
]]

--==================================================
-- Services / references
--==================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local existingGui = playerGui:FindFirstChild("TeleportMenu")
if existingGui then
	existingGui:Destroy()
end

--==================================================
-- Config / state
--==================================================
local DEFAULT_COLORS = {
	frameBackground = Color3.fromRGB(30, 30, 30),
	titleBackground = Color3.fromRGB(40, 40, 40),
	buttonBackground = Color3.fromRGB(70, 110, 200),
	secondaryButtonBackground = Color3.fromRGB(70, 170, 110),
	statusBackground = Color3.fromRGB(45, 45, 45),
	textColor = Color3.fromRGB(255, 255, 255),
	espMarkerColor = Color3.fromRGB(255, 80, 80),
	espLineColor = Color3.fromRGB(255, 80, 80),
	closeButtonBackground = Color3.fromRGB(170, 60, 60),
	openButtonBackground = Color3.fromRGB(45, 45, 45),
}

local DEFAULT_CONFIG = {
	savedPosition = nil,
	savedBasePosition = nil,
	espEnabled = false,
	menuPosition = { scaleX = 0, offsetX = 120, scaleY = 0, offsetY = 120 },
	openButtonPosition = { scaleX = 0, offsetX = 20, scaleY = 0, offsetY = 20 },
	settingsOpen = false,
	colors = DEFAULT_COLORS,
}

local DEFAULT_BASE_OFFSET = 3.5
local ESP_MARKER_SIZE = Vector3.new(4, 8, 4)
local ESP_MARKER_TRANSPARENCY = 0.55

local state = {
	savedPosition = nil,
	savedBasePosition = nil,
	espEnabled = false,
	settingsOpen = false,
	colors = {},
	menuPosition = UDim2.new(
		DEFAULT_CONFIG.menuPosition.scaleX,
		DEFAULT_CONFIG.menuPosition.offsetX,
		DEFAULT_CONFIG.menuPosition.scaleY,
		DEFAULT_CONFIG.menuPosition.offsetY
	),
	openButtonPosition = UDim2.new(
		DEFAULT_CONFIG.openButtonPosition.scaleX,
		DEFAULT_CONFIG.openButtonPosition.offsetX,
		DEFAULT_CONFIG.openButtonPosition.scaleY,
		DEFAULT_CONFIG.openButtonPosition.offsetY
	),
}

local ui = {}
local dynamicButtons = {}
local colorEditors = {}
local activeColorSlider = nil
local espObjects = {
	folder = nil,
	marker = nil,
	linePart = nil,
	targetAttachment = nil,
	hrpAttachment = nil,
	beam = nil,
	renderConnection = nil,
	characterConnection = nil,
	viewportConnection = nil,
	cameraConnection = nil,
}

local CONFIG_SCOPE = tostring(game.PlaceId ~= 0 and game.PlaceId or game.GameId)
local CONFIG_FILE_NAME = string.format("teleport_menu_config_%s.json", CONFIG_SCOPE)

for colorName, colorValue in pairs(DEFAULT_COLORS) do
	state.colors[colorName] = colorValue
end

--==================================================
-- Serialization helpers
--==================================================
local function color3ToTable(color)
	return {
		r = math.floor(color.R * 255 + 0.5),
		g = math.floor(color.G * 255 + 0.5),
		b = math.floor(color.B * 255 + 0.5),
	}
end

local function tableToColor3(data, fallback)
	if type(data) ~= "table" then
		return fallback
	end

	local r = tonumber(data.r)
	local g = tonumber(data.g)
	local b = tonumber(data.b)
	if not r or not g or not b then
		return fallback
	end

	return Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
end

local function cframeToTable(cframe)
	return { cframe:GetComponents() }
end

local function tableToCFrame(data)
	if type(data) ~= "table" or #data ~= 12 then
		return nil
	end

	for index = 1, 12 do
		if type(data[index]) ~= "number" then
			return nil
		end
	end

	return CFrame.new(table.unpack(data))
end

local function vector3ToTable(vector)
	return {
		x = vector.X,
		y = vector.Y,
		z = vector.Z,
	}
end

local function tableToVector3(data)
	if type(data) ~= "table" then
		return nil
	end

	local x = tonumber(data.x)
	local y = tonumber(data.y)
	local z = tonumber(data.z)
	if not x or not y or not z then
		return nil
	end

	return Vector3.new(x, y, z)
end

local function udim2ToTable(udim)
	return {
		scaleX = udim.X.Scale,
		offsetX = udim.X.Offset,
		scaleY = udim.Y.Scale,
		offsetY = udim.Y.Offset,
	}
end

local function tableToUDim2(data, fallback)
	if type(data) ~= "table" then
		return fallback
	end

	local scaleX = tonumber(data.scaleX)
	local offsetX = tonumber(data.offsetX)
	local scaleY = tonumber(data.scaleY)
	local offsetY = tonumber(data.offsetY)
	if not scaleX or not offsetX or not scaleY or not offsetY then
		return fallback
	end

	return UDim2.new(scaleX, offsetX, scaleY, offsetY)
end

local function cloneDefaultColors()
	local output = {}
	for name, color in pairs(DEFAULT_COLORS) do
		output[name] = color
	end
	return output
end

local function estimateBasePositionFromCFrame(cframe)
	if not cframe then
		return nil
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoidRootPart then
		local offset = humanoidRootPart.Size.Y * 0.5 + humanoid.HipHeight
		return cframe.Position - Vector3.new(0, offset, 0)
	end

	return cframe.Position - Vector3.new(0, DEFAULT_BASE_OFFSET, 0)
end

local function applyLoadedConfig(config)
	config = config or {}
	state.savedPosition = tableToCFrame(config.savedPosition)
	state.savedBasePosition = tableToVector3(config.savedBasePosition)
		or estimateBasePositionFromCFrame(state.savedPosition)
	state.espEnabled = config.espEnabled == true
	state.menuPosition = tableToUDim2(config.menuPosition, state.menuPosition)
	state.openButtonPosition = tableToUDim2(config.openButtonPosition, state.openButtonPosition)
	state.settingsOpen = config.settingsOpen == true

	local colors = cloneDefaultColors()
	if type(config.colors) == "table" then
		for colorName, defaultColor in pairs(DEFAULT_COLORS) do
			colors[colorName] = tableToColor3(config.colors[colorName], defaultColor)
		end
	end
	state.colors = colors
end

local function buildConfigTable()
	local colors = {}
	for name, color in pairs(state.colors) do
		colors[name] = color3ToTable(color)
	end

	return {
		savedPosition = state.savedPosition and cframeToTable(state.savedPosition) or nil,
		savedBasePosition = state.savedBasePosition and vector3ToTable(state.savedBasePosition) or nil,
		espEnabled = state.espEnabled,
		menuPosition = udim2ToTable(ui.mainFrame and ui.mainFrame.Position or state.menuPosition),
		openButtonPosition = udim2ToTable(ui.openButton and ui.openButton.Position or state.openButtonPosition),
		settingsOpen = state.settingsOpen,
		colors = colors,
	}
end

--==================================================
-- Save / load config
--==================================================
local function persistenceAvailable()
	return type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"
end

local function loadConfig()
	if not persistenceAvailable() then
		return false, "Config persistence unavailable"
	end

	local success, result = pcall(function()
		if not isfile(CONFIG_FILE_NAME) then
			return nil
		end

		local content = readfile(CONFIG_FILE_NAME)
		if not content or content == "" then
			return nil
		end

		return HttpService:JSONDecode(content)
	end)

	if not success then
		return false, "Failed to load config"
	end

	if result then
		applyLoadedConfig(result)
		return true, "Config loaded"
	end

	return false, "No config found"
end

local function saveConfig()
	if not persistenceAvailable() then
		return false, "Saving unavailable in this environment"
	end

	local success = pcall(function()
		local payload = HttpService:JSONEncode(buildConfigTable())
		writefile(CONFIG_FILE_NAME, payload)
	end)

	if success then
		return true, "Config saved"
	end

	return false, "Failed to save config"
end

--==================================================
-- Helper functions
--==================================================
local function setStatus(message)
	if ui.statusLabel then
		ui.statusLabel.Text = message
	end
end

local function getViewportSize()
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1920, 1080)
end

local function clampAxis(value, objectSize, viewportSize)
	local visibleMargin = 24
	local minPosition = -(objectSize - visibleMargin)
	local maxPosition = viewportSize - visibleMargin
	return math.clamp(value, minPosition, maxPosition)
end

local function clampGuiPosition(guiObject, desiredPosition)
	local viewportSize = getViewportSize()
	local absoluteSize = guiObject.AbsoluteSize
	local absX = desiredPosition.X.Scale * viewportSize.X + desiredPosition.X.Offset
	local absY = desiredPosition.Y.Scale * viewportSize.Y + desiredPosition.Y.Offset

	absX = clampAxis(absX, absoluteSize.X, viewportSize.X)
	absY = clampAxis(absY, absoluteSize.Y, viewportSize.Y)

	return UDim2.new(0, math.floor(absX + 0.5), 0, math.floor(absY + 0.5))
end

local function reclampVisibleUi()
	if ui.mainFrame then
		ui.mainFrame.Position = clampGuiPosition(ui.mainFrame, ui.mainFrame.Position)
		state.menuPosition = ui.mainFrame.Position
	end
	if ui.openButton then
		ui.openButton.Position = clampGuiPosition(ui.openButton, ui.openButton.Position)
		state.openButtonPosition = ui.openButton.Position
	end
end

local function bindViewportClamp()
	if espObjects.viewportConnection then
		espObjects.viewportConnection:Disconnect()
		espObjects.viewportConnection = nil
	end
	if espObjects.cameraConnection then
		espObjects.cameraConnection:Disconnect()
		espObjects.cameraConnection = nil
	end

	local function connectCamera(camera)
		if espObjects.viewportConnection then
			espObjects.viewportConnection:Disconnect()
			espObjects.viewportConnection = nil
		end

		if camera then
			espObjects.viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(reclampVisibleUi)
		end
	end

	connectCamera(Workspace.CurrentCamera)
	espObjects.cameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		connectCamera(Workspace.CurrentCamera)
		reclampVisibleUi()
	end)
end

local function getCharacter()
	return localPlayer.Character
end

local function getHumanoidRootPart(timeout)
	local character = getCharacter()
	if not character then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart then
		return humanoidRootPart
	end

	if timeout and timeout > 0 then
		local success, result = pcall(function()
			return character:WaitForChild("HumanoidRootPart", timeout)
		end)
		if success then
			return result
		end
	end

	return nil
end

local function getHumanoid(timeout)
	local character = getCharacter()
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end

	if timeout and timeout > 0 then
		local success, result = pcall(function()
			return character:WaitForChild("Humanoid", timeout)
		end)
		if success then
			return result
		end
	end

	return nil
end

local function getReadableTextColor(backgroundColor)
	local brightness = (backgroundColor.R * 0.299) + (backgroundColor.G * 0.587) + (backgroundColor.B * 0.114)
	return brightness > 0.6 and Color3.fromRGB(18, 18, 18) or Color3.fromRGB(255, 255, 255)
end

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 8)
	corner.Parent = instance
	return corner
end

local function createStroke(instance, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.fromRGB(65, 65, 65)
	stroke.Thickness = thickness or 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

local function getSavedBasePosition()
	return state.savedBasePosition or estimateBasePositionFromCFrame(state.savedPosition)
end

local function computeFootBasePosition(humanoidRootPart, humanoid)
	local verticalOffset = humanoidRootPart.Size.Y * 0.5 + math.max(humanoid.HipHeight, 0)
	local estimatedBase = humanoidRootPart.Position - Vector3.new(0, verticalOffset, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { getCharacter() }
	raycastParams.IgnoreWater = false

	local rayDistance = math.max(verticalOffset + 4, 8)
	local raycastResult = Workspace:Raycast(humanoidRootPart.Position, Vector3.new(0, -rayDistance, 0), raycastParams)
	if raycastResult then
		local groundPosition = raycastResult.Position
		if groundPosition.Y <= humanoidRootPart.Position.Y + 0.5 then
			return Vector3.new(humanoidRootPart.Position.X, groundPosition.Y, humanoidRootPart.Position.Z)
		end
	end

	return estimatedBase
end

--==================================================
-- UI builders
--==================================================
local function createFrame(name, parent, size, position, backgroundColor, transparency)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position or UDim2.new()
	frame.BackgroundColor3 = backgroundColor or Color3.fromRGB(40, 40, 40)
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function createButton(name, parent, size, position, text, backgroundColor, textColor)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position or UDim2.new()
	button.BackgroundColor3 = backgroundColor
	button.BorderSizePixel = 0
	button.Text = text
	button.TextSize = 17
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = textColor or state.colors.textColor
	button.AutoButtonColor = true
	button.Parent = parent
	addCorner(button)
	return button
end

local function createLabel(name, parent, size, position, text, textSize, backgroundColor)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position or UDim2.new()
	label.BackgroundColor3 = backgroundColor or Color3.fromRGB(45, 45, 45)
	label.BorderSizePixel = 0
	label.Text = text or ""
	label.TextSize = textSize or 16
	label.Font = Enum.Font.Gotham
	label.TextColor3 = state.colors.textColor
	label.Parent = parent
	addCorner(label)
	return label
end

local function createTextBox(name, parent, size, position, text)
	local textBox = Instance.new("TextBox")
	textBox.Name = name
	textBox.Size = size
	textBox.Position = position or UDim2.new()
	textBox.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
	textBox.BorderSizePixel = 0
	textBox.ClearTextOnFocus = false
	textBox.Text = text or ""
	textBox.PlaceholderText = "0-255"
	textBox.TextSize = 13
	textBox.Font = Enum.Font.Gotham
	textBox.TextColor3 = state.colors.textColor
	textBox.Parent = parent
	addCorner(textBox, UDim.new(0, 6))
	createStroke(textBox, Color3.fromRGB(55, 55, 55), 1)
	return textBox
end

local function registerDynamicButton(button, role)
	table.insert(dynamicButtons, { instance = button, role = role })
	return button
end

--==================================================
-- Drag logic
--==================================================
local dragging = false
local dragInputType = nil
local dragStart = nil
local startPosition = nil
local dragTarget = nil
local dragFinishedCallback = nil

local function finishDrag()
	if not dragTarget then
		dragging = false
		dragInputType = nil
		dragFinishedCallback = nil
		return
	end

	dragTarget.Position = clampGuiPosition(dragTarget, dragTarget.Position)
	if dragFinishedCallback then
		dragFinishedCallback(dragTarget.Position)
	end

	dragging = false
	dragInputType = nil
	dragStart = nil
	startPosition = nil
	dragTarget = nil
	dragFinishedCallback = nil
end

local function beginDrag(input, target, onFinished)
	if dragging and dragTarget == target and dragInputType == input.UserInputType then
		return
	end

	dragging = true
	dragInputType = input.UserInputType
	dragStart = input.Position
	startPosition = target.Position
	dragTarget = target
	dragFinishedCallback = onFinished
end

local function makeDraggable(handle, target, onFinished)
	handle.Active = true
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input, target, onFinished)
		end
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if dragging and dragTarget then
		local isMouseDrag = dragInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
		local isTouchDrag = dragInputType == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch
		if isMouseDrag or isTouchDrag then
			local delta = input.Position - dragStart
			local desiredPosition = UDim2.new(
				0,
				startPosition.X.Offset + delta.X,
				0,
				startPosition.Y.Offset + delta.Y
			)
			dragTarget.Position = desiredPosition
		end
	end

	if activeColorSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		activeColorSlider:update(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if activeColorSlider and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		activeColorSlider = nil
	end

	if dragging then
		local isMouseRelease = dragInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1
		local isTouchRelease = dragInputType == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch
		if isMouseRelease or isTouchRelease then
			finishDrag()
		end
	end
end)

--==================================================
-- ESP logic
--==================================================
local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

local function clearEspInstances()
	disconnectConnection(espObjects.renderConnection)
	espObjects.renderConnection = nil

	if espObjects.hrpAttachment then
		espObjects.hrpAttachment:Destroy()
		espObjects.hrpAttachment = nil
	end

	if espObjects.folder then
		espObjects.folder:Destroy()
	end

	espObjects.folder = nil
	espObjects.marker = nil
	espObjects.linePart = nil
	espObjects.targetAttachment = nil
	espObjects.beam = nil
end

local function ensureEspFolder()
	if espObjects.folder and espObjects.folder.Parent then
		return espObjects.folder
	end

	local folder = Instance.new("Folder")
	folder.Name = "TeleportMenuESP"
	folder.Parent = Workspace
	espObjects.folder = folder
	return folder
end

local function createEspObjects()
	local folder = ensureEspFolder()

	local marker = Instance.new("Part")
	marker.Name = "SavedPositionMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Transparency = ESP_MARKER_TRANSPARENCY
	marker.Material = Enum.Material.ForceField
	marker.Size = ESP_MARKER_SIZE
	marker.Color = state.colors.espMarkerColor
	marker.Parent = folder

	local linePart = Instance.new("Part")
	linePart.Name = "SavedPositionLineTarget"
	linePart.Anchored = true
	linePart.CanCollide = false
	linePart.CanTouch = false
	linePart.CanQuery = false
	linePart.Transparency = 1
	linePart.Size = Vector3.new(0.2, 0.2, 0.2)
	linePart.Parent = folder

	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = "TargetAttachment"
	targetAttachment.Parent = linePart

	local beam = Instance.new("Beam")
	beam.Name = "SavedPositionBeam"
	beam.FaceCamera = true
	beam.Width0 = 0.12
	beam.Width1 = 0.12
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new(0.25)
	beam.Color = ColorSequence.new(state.colors.espLineColor)
	beam.Attachment1 = targetAttachment
	beam.Parent = folder

	espObjects.marker = marker
	espObjects.linePart = linePart
	espObjects.targetAttachment = targetAttachment
	espObjects.beam = beam
end

local function attachBeamToHumanoidRootPart()
	local humanoidRootPart = getHumanoidRootPart(1)
	if not humanoidRootPart or not espObjects.beam then
		return false
	end

	if espObjects.hrpAttachment then
		espObjects.hrpAttachment:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "SavedPositionSourceAttachment"
	attachment.Position = Vector3.new(0, 0.5, 0)
	attachment.Parent = humanoidRootPart
	espObjects.hrpAttachment = attachment
	espObjects.beam.Attachment0 = attachment
	return true
end

local function updateEspVisuals()
	if not state.espEnabled or not state.savedPosition or not espObjects.marker or not espObjects.linePart then
		return
	end

	local savedBasePosition = getSavedBasePosition()
	if not savedBasePosition then
		return
	end

	espObjects.marker.CFrame = CFrame.new(savedBasePosition + Vector3.new(0, espObjects.marker.Size.Y * 0.5, 0))
	espObjects.linePart.CFrame = CFrame.new(savedBasePosition)
	espObjects.marker.Color = state.colors.espMarkerColor

	if espObjects.beam then
		espObjects.beam.Color = ColorSequence.new(state.colors.espLineColor)
		if not espObjects.hrpAttachment or not espObjects.hrpAttachment.Parent then
			attachBeamToHumanoidRootPart()
		end
	end
end

local function startEsp()
	if not state.savedPosition then
		clearEspInstances()
		setStatus("No saved position")
		return
	end

	clearEspInstances()
	createEspObjects()
	attachBeamToHumanoidRootPart()
	updateEspVisuals()

	espObjects.renderConnection = RunService.RenderStepped:Connect(function()
		if state.espEnabled then
			updateEspVisuals()
		end
	end)
end

local function stopEsp()
	clearEspInstances()
end

local function refreshEspState()
	if state.espEnabled then
		startEsp()
	else
		stopEsp()
	end
end

--==================================================
-- Settings logic
--==================================================
local function updateEspButtonVisual()
	if not ui.espButton then
		return
	end

	ui.espButton.BackgroundColor3 = state.espEnabled and Color3.fromRGB(90, 205, 115) or Color3.fromRGB(210, 75, 75)
	ui.espButton.TextColor3 = Color3.fromRGB(0, 0, 0)
	ui.espButton.Text = state.espEnabled and "ESP: ON" or "ESP: OFF"
end

local function updateColorEditorVisuals(editor)
	local color = state.colors[editor.colorKey]
	editor.preview.BackgroundColor3 = color
	editor.inputs[1].Text = tostring(math.floor(color.R * 255 + 0.5))
	editor.inputs[2].Text = tostring(math.floor(color.G * 255 + 0.5))
	editor.inputs[3].Text = tostring(math.floor(color.B * 255 + 0.5))
	for index, fill in ipairs(editor.sliderFills) do
		local channelValue = index == 1 and color.R or index == 2 and color.G or color.B
		fill.Size = UDim2.new(channelValue, 0, 1, 0)
	end
end

local function updateSettingsCanvas()
	if ui.settingsLayout and ui.settingsScroll then
		ui.settingsScroll.CanvasSize = UDim2.new(0, 0, 0, ui.settingsLayout.AbsoluteContentSize.Y + 8)
	end
end

local function applyTheme()
	if not ui.mainFrame then
		return
	end

	ui.mainFrame.BackgroundColor3 = state.colors.frameBackground
	ui.titleBar.BackgroundColor3 = state.colors.titleBackground
	ui.titleBarFill.BackgroundColor3 = state.colors.titleBackground
	ui.titleLabel.TextColor3 = state.colors.textColor
	ui.statusLabel.BackgroundColor3 = state.colors.statusBackground
	ui.statusLabel.TextColor3 = state.colors.textColor
	ui.settingsContainer.BackgroundColor3 = state.colors.frameBackground
	ui.settingsHeaderLabel.TextColor3 = state.colors.textColor
	ui.settingsDivider.BackgroundColor3 = state.colors.titleBackground
	ui.openButton.BackgroundColor3 = state.colors.openButtonBackground
	ui.openButton.TextColor3 = state.colors.textColor
	ui.closeButton.BackgroundColor3 = state.colors.closeButtonBackground
	ui.closeButton.TextColor3 = getReadableTextColor(state.colors.closeButtonBackground)

	for _, buttonInfo in ipairs(dynamicButtons) do
		if buttonInfo.role == "primary" or buttonInfo.role == "toggle" then
			buttonInfo.instance.BackgroundColor3 = state.colors.buttonBackground
			buttonInfo.instance.TextColor3 = state.colors.textColor
		elseif buttonInfo.role == "secondary" then
			buttonInfo.instance.BackgroundColor3 = state.colors.secondaryButtonBackground
			buttonInfo.instance.TextColor3 = state.colors.textColor
		elseif buttonInfo.role == "open" then
			buttonInfo.instance.BackgroundColor3 = state.colors.openButtonBackground
			buttonInfo.instance.TextColor3 = state.colors.textColor
		elseif buttonInfo.role == "close" then
			buttonInfo.instance.BackgroundColor3 = state.colors.closeButtonBackground
			buttonInfo.instance.TextColor3 = getReadableTextColor(state.colors.closeButtonBackground)
		elseif buttonInfo.role == "esp" then
			updateEspButtonVisual()
		end
	end

	for _, editor in pairs(colorEditors) do
		editor.container.BackgroundColor3 = Color3.fromRGB(36, 36, 36)
		editor.content.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
		editor.toggle.TextColor3 = state.colors.textColor
		editor.titleLabel.TextColor3 = state.colors.textColor
		for _, rowLabel in ipairs(editor.rowLabels) do
			rowLabel.TextColor3 = state.colors.textColor
		end
		for _, input in ipairs(editor.inputs) do
			input.TextColor3 = state.colors.textColor
		end
		updateColorEditorVisuals(editor)
	end

	updateEspVisuals()
end

local function updateMenuLayout()
	if not ui.mainFrame then
		return
	end

	local settingsHeight = state.settingsOpen and 380 or 0
	ui.settingsContainer.Visible = state.settingsOpen
	ui.settingsContainer.Size = UDim2.new(1, -20, 0, settingsHeight)
	ui.mainFrame.Size = UDim2.new(0, 340, 0, 312 + settingsHeight)
	ui.mainFrame.Position = clampGuiPosition(ui.mainFrame, ui.mainFrame.Position)
	state.menuPosition = ui.mainFrame.Position
	ui.settingsButton.Text = state.settingsOpen and "Settings ▲" or "Settings ▼"
	updateSettingsCanvas()
end

local function setSettingsOpen(isOpen)
	state.settingsOpen = isOpen
	updateMenuLayout()
end

local function parseChannelValue(text)
	local numeric = tonumber(text)
	if not numeric then
		return nil
	end
	return math.clamp(math.floor(numeric + 0.5), 0, 255)
end

local function applyColorValue(colorKey, color)
	state.colors[colorKey] = color
	applyTheme()
	setStatus(string.format("Updated %s", colorKey))
end

local function commitEditorColor(editor)
	local r = parseChannelValue(editor.inputs[1].Text)
	local g = parseChannelValue(editor.inputs[2].Text)
	local b = parseChannelValue(editor.inputs[3].Text)
	if not r or not g or not b then
		setStatus("Enter RGB values 0-255")
		updateColorEditorVisuals(editor)
		return
	end

	applyColorValue(editor.colorKey, Color3.fromRGB(r, g, b))
	updateColorEditorVisuals(editor)
end

local function toggleEditorVisibility(selectedKey)
	for colorKey, editor in pairs(colorEditors) do
		local visible = colorKey == selectedKey and not editor.content.Visible
		editor.content.Visible = visible
		editor.container.Size = visible and UDim2.new(1, 0, 0, 118) or UDim2.new(1, 0, 0, 36)
		editor.toggle.Text = visible and "Hide" or "Edit"
		updateSettingsCanvas()
	end
end

local function createColorEditor(parent, colorKey, displayName)
	local container = createFrame(displayName:gsub(" ", "") .. "Editor", parent, UDim2.new(1, 0, 0, 36), UDim2.new(), Color3.fromRGB(36, 36, 36))
	addCorner(container, UDim.new(0, 8))
	createStroke(container, Color3.fromRGB(60, 60, 60), 1)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, -80, 0, 30)
	titleLabel.Position = UDim2.new(0, 10, 0, 3)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = displayName
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 14
	titleLabel.TextColor3 = state.colors.textColor
	titleLabel.Parent = container

	local preview = createFrame("Preview", container, UDim2.new(0, 20, 0, 20), UDim2.new(1, -74, 0, 8), state.colors[colorKey])
	addCorner(preview, UDim.new(0, 6))
	createStroke(preview, Color3.fromRGB(15, 15, 15), 1)

	local toggle = createButton("ToggleButton", container, UDim2.new(0, 42, 0, 24), UDim2.new(1, -48, 0, 6), "Edit", state.colors.buttonBackground, state.colors.textColor)
	toggle.TextSize = 12
	registerDynamicButton(toggle, "toggle")

	local content = createFrame("Content", container, UDim2.new(1, -12, 0, 76), UDim2.new(0, 6, 0, 36), Color3.fromRGB(28, 28, 28))
	content.Visible = false
	addCorner(content, UDim.new(0, 8))

	local rowLabels = {}
	local inputs = {}
	local sliderBars = {}
	local sliderFills = {}

	for index, channelName in ipairs({ "R", "G", "B" }) do
		local rowY = (index - 1) * 24

		local rowLabel = Instance.new("TextLabel")
		rowLabel.Name = channelName .. "Label"
		rowLabel.Size = UDim2.new(0, 18, 0, 18)
		rowLabel.Position = UDim2.new(0, 8, 0, rowY + 2)
		rowLabel.BackgroundTransparency = 1
		rowLabel.Text = channelName
		rowLabel.Font = Enum.Font.GothamBold
		rowLabel.TextSize = 14
		rowLabel.TextColor3 = state.colors.textColor
		rowLabel.Parent = content
		table.insert(rowLabels, rowLabel)

		local sliderBar = createFrame(channelName .. "SliderBar", content, UDim2.new(1, -120, 0, 8), UDim2.new(0, 30, 0, rowY + 8), Color3.fromRGB(55, 55, 55))
		addCorner(sliderBar, UDim.new(0, 8))
		table.insert(sliderBars, sliderBar)

		local sliderFillColor = channelName == "R" and Color3.fromRGB(255, 80, 80)
			or channelName == "G" and Color3.fromRGB(80, 255, 80)
			or Color3.fromRGB(80, 140, 255)
		local sliderFill = createFrame(channelName .. "SliderFill", sliderBar, UDim2.new(0, 0, 1, 0), UDim2.new(), sliderFillColor)
		addCorner(sliderFill, UDim.new(0, 8))
		table.insert(sliderFills, sliderFill)

		local input = createTextBox(channelName .. "Input", content, UDim2.new(0, 64, 0, 20), UDim2.new(1, -72, 0, rowY), "0")
		table.insert(inputs, input)
	end

	local editor = {
		colorKey = colorKey,
		displayName = displayName,
		container = container,
		titleLabel = titleLabel,
		preview = preview,
		toggle = toggle,
		content = content,
		rowLabels = rowLabels,
		inputs = inputs,
		sliderBars = sliderBars,
		sliderFills = sliderFills,
	}
	colorEditors[colorKey] = editor

	local function setFromSlider(channelIndex, pointerX)
		local sliderBar = editor.sliderBars[channelIndex]
		local relativeX = math.clamp(pointerX - sliderBar.AbsolutePosition.X, 0, sliderBar.AbsoluteSize.X)
		local percentage = sliderBar.AbsoluteSize.X > 0 and (relativeX / sliderBar.AbsoluteSize.X) or 0
		local channelValue = math.floor(percentage * 255 + 0.5)
		editor.inputs[channelIndex].Text = tostring(channelValue)
		commitEditorColor(editor)
	end

	for index, sliderBar in ipairs(editor.sliderBars) do
		sliderBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				activeColorSlider = {
					update = function(pointerX)
						setFromSlider(index, pointerX)
					end,
				}
				setFromSlider(index, input.Position.X)
			end
		end)
	end

	for _, input in ipairs(editor.inputs) do
		input.FocusLost:Connect(function()
			commitEditorColor(editor)
		end)
	end

	toggle.MouseButton1Click:Connect(function()
		toggleEditorVisibility(colorKey)
	end)

	updateColorEditorVisuals(editor)
	return editor
end

--==================================================
-- UI construction
--==================================================
local function buildInterface()
	ui.screenGui = Instance.new("ScreenGui")
	ui.screenGui.Name = "TeleportMenu"
	ui.screenGui.ResetOnSpawn = false
	ui.screenGui.IgnoreGuiInset = true
	ui.screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ui.screenGui.Parent = playerGui

	ui.openButton = createButton("OpenButton", ui.screenGui, UDim2.new(0, 140, 0, 44), state.openButtonPosition, "Open Menu", state.colors.openButtonBackground, state.colors.textColor)
	ui.openButton.Active = true
	registerDynamicButton(ui.openButton, "open")

	ui.mainFrame = createFrame("MainFrame", ui.screenGui, UDim2.new(0, 340, 0, 312), state.menuPosition, state.colors.frameBackground)
	ui.mainFrame.Active = true
	addCorner(ui.mainFrame, UDim.new(0, 10))
	createStroke(ui.mainFrame, Color3.fromRGB(55, 55, 55), 1)

	ui.titleBar = createFrame("TitleBar", ui.mainFrame, UDim2.new(1, 0, 0, 40), UDim2.new(), state.colors.titleBackground)
	ui.titleBar.Active = true
	addCorner(ui.titleBar, UDim.new(0, 10))

	ui.titleBarFill = createFrame("TitleBarFill", ui.titleBar, UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 20), state.colors.titleBackground)

	ui.titleLabel = Instance.new("TextLabel")
	ui.titleLabel.Name = "TitleLabel"
	ui.titleLabel.Size = UDim2.new(1, -50, 1, 0)
	ui.titleLabel.Position = UDim2.new(0, 12, 0, 0)
	ui.titleLabel.BackgroundTransparency = 1
	ui.titleLabel.Text = "Teleport Menu"
	ui.titleLabel.TextColor3 = state.colors.textColor
	ui.titleLabel.TextSize = 18
	ui.titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	ui.titleLabel.Font = Enum.Font.GothamBold
	ui.titleLabel.Parent = ui.titleBar

	ui.closeButton = createButton("CloseButton", ui.titleBar, UDim2.new(0, 30, 0, 30), UDim2.new(1, -36, 0, 5), "X", state.colors.closeButtonBackground, getReadableTextColor(state.colors.closeButtonBackground))
	ui.closeButton.TextSize = 16
	registerDynamicButton(ui.closeButton, "close")

	ui.statusLabel = createLabel("StatusLabel", ui.mainFrame, UDim2.new(1, -20, 0, 28), UDim2.new(0, 10, 0, 55), "Ready", 16, state.colors.statusBackground)
	ui.statusLabel.TextWrapped = true

	ui.setPositionButton = createButton("SetPositionButton", ui.mainFrame, UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 0, 95), "Set Position", state.colors.buttonBackground, state.colors.textColor)
	registerDynamicButton(ui.setPositionButton, "primary")

	ui.teleportButton = createButton("TeleportButton", ui.mainFrame, UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 0, 141), "TP to Position", state.colors.secondaryButtonBackground, state.colors.textColor)
	registerDynamicButton(ui.teleportButton, "secondary")

	ui.espButton = createButton("ESPButton", ui.mainFrame, UDim2.new(0.5, -15, 0, 40), UDim2.new(0, 10, 0, 187), "ESP: OFF", Color3.fromRGB(210, 75, 75), Color3.fromRGB(0, 0, 0))
	registerDynamicButton(ui.espButton, "esp")

	ui.saveConfigButton = createButton("SaveConfigButton", ui.mainFrame, UDim2.new(0.5, -15, 0, 40), UDim2.new(0.5, 5, 0, 187), "Save Config", state.colors.buttonBackground, state.colors.textColor)
	registerDynamicButton(ui.saveConfigButton, "primary")

	ui.settingsButton = createButton("SettingsButton", ui.mainFrame, UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 0, 233), "Settings ▼", state.colors.buttonBackground, state.colors.textColor)
	registerDynamicButton(ui.settingsButton, "primary")

	ui.settingsContainer = createFrame("SettingsContainer", ui.mainFrame, UDim2.new(1, -20, 0, 0), UDim2.new(0, 10, 0, 279), state.colors.frameBackground)
	ui.settingsContainer.Visible = false
	addCorner(ui.settingsContainer, UDim.new(0, 10))
	createStroke(ui.settingsContainer, Color3.fromRGB(55, 55, 55), 1)

	ui.settingsHeaderLabel = Instance.new("TextLabel")
	ui.settingsHeaderLabel.Name = "SettingsHeaderLabel"
	ui.settingsHeaderLabel.Size = UDim2.new(1, 0, 0, 24)
	ui.settingsHeaderLabel.Position = UDim2.new(0, 0, 0, 0)
	ui.settingsHeaderLabel.BackgroundTransparency = 1
	ui.settingsHeaderLabel.Text = "Settings"
	ui.settingsHeaderLabel.Font = Enum.Font.GothamBold
	ui.settingsHeaderLabel.TextSize = 16
	ui.settingsHeaderLabel.TextColor3 = state.colors.textColor
	ui.settingsHeaderLabel.Parent = ui.settingsContainer

	ui.settingsDivider = createFrame("SettingsDivider", ui.settingsContainer, UDim2.new(1, 0, 0, 2), UDim2.new(0, 0, 0, 28), state.colors.titleBackground)

	ui.settingsScroll = Instance.new("ScrollingFrame")
	ui.settingsScroll.Name = "SettingsScroll"
	ui.settingsScroll.Size = UDim2.new(1, -4, 1, -34)
	ui.settingsScroll.Position = UDim2.new(0, 0, 0, 34)
	ui.settingsScroll.BackgroundTransparency = 1
	ui.settingsScroll.BorderSizePixel = 0
	ui.settingsScroll.ScrollBarThickness = 6
	ui.settingsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	ui.settingsScroll.Parent = ui.settingsContainer

	ui.settingsLayout = Instance.new("UIListLayout")
	ui.settingsLayout.Padding = UDim.new(0, 6)
	ui.settingsLayout.FillDirection = Enum.FillDirection.Vertical
	ui.settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ui.settingsLayout.Parent = ui.settingsScroll
	ui.settingsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSettingsCanvas)

	createColorEditor(ui.settingsScroll, "frameBackground", "Menu Background")
	createColorEditor(ui.settingsScroll, "titleBackground", "Title Background")
	createColorEditor(ui.settingsScroll, "statusBackground", "Status Background")
	createColorEditor(ui.settingsScroll, "buttonBackground", "Button Color")
	createColorEditor(ui.settingsScroll, "secondaryButtonBackground", "Teleport Button")
	createColorEditor(ui.settingsScroll, "openButtonBackground", "Open Button")
	createColorEditor(ui.settingsScroll, "closeButtonBackground", "Close Button")
	createColorEditor(ui.settingsScroll, "textColor", "Text Color")
	createColorEditor(ui.settingsScroll, "espMarkerColor", "ESP Marker")
	createColorEditor(ui.settingsScroll, "espLineColor", "ESP Line")

	applyTheme()
	updateEspButtonVisual()
	setSettingsOpen(state.settingsOpen)
	ui.mainFrame.Position = clampGuiPosition(ui.mainFrame, state.menuPosition)
	ui.openButton.Position = clampGuiPosition(ui.openButton, state.openButtonPosition)
	state.menuPosition = ui.mainFrame.Position
	state.openButtonPosition = ui.openButton.Position
	bindViewportClamp()
end

--==================================================
-- Button events
--==================================================
local function connectEvents()
	makeDraggable(ui.mainFrame, ui.mainFrame, function(newPosition)
		state.menuPosition = newPosition
	end)
	makeDraggable(ui.titleBar, ui.mainFrame, function(newPosition)
		state.menuPosition = newPosition
	end)
	makeDraggable(ui.openButton, ui.openButton, function(newPosition)
		state.openButtonPosition = newPosition
	end)

	ui.setPositionButton.MouseButton1Click:Connect(function()
		local humanoidRootPart = getHumanoidRootPart(1)
		local humanoid = getHumanoid(1)
		if not humanoidRootPart or not humanoid then
			setStatus("Character not ready")
			return
		end

		state.savedPosition = humanoidRootPart.CFrame
		state.savedBasePosition = computeFootBasePosition(humanoidRootPart, humanoid)
		setStatus("Position saved")
		if state.espEnabled then
			refreshEspState()
		end
	end)

	ui.teleportButton.MouseButton1Click:Connect(function()
		if not state.savedPosition then
			setStatus("No position saved")
			return
		end

		local humanoidRootPart = getHumanoidRootPart(1)
		if not humanoidRootPart then
			setStatus("Character not ready")
			return
		end

		humanoidRootPart.CFrame = state.savedPosition
		setStatus("Teleported to saved position")
	end)

	ui.espButton.MouseButton1Click:Connect(function()
		state.espEnabled = not state.espEnabled
		updateEspButtonVisual()
		refreshEspState()
		if state.espEnabled and state.savedPosition then
			setStatus("ESP enabled")
		elseif not state.espEnabled then
			setStatus("ESP disabled")
		end
	end)

	ui.saveConfigButton.MouseButton1Click:Connect(function()
		state.menuPosition = ui.mainFrame.Position
		state.openButtonPosition = ui.openButton.Position
		local success, message = saveConfig()
		setStatus(message)
		if not success then
			warn(message)
		end
	end)

	ui.settingsButton.MouseButton1Click:Connect(function()
		setSettingsOpen(not state.settingsOpen)
		setStatus(state.settingsOpen and "Settings opened" or "Settings closed")
	end)

	ui.openButton.MouseButton1Click:Connect(function()
		ui.mainFrame.Visible = true
		ui.openButton.Visible = false
		ui.mainFrame.Position = clampGuiPosition(ui.mainFrame, ui.mainFrame.Position)
		state.menuPosition = ui.mainFrame.Position
	end)

	ui.closeButton.MouseButton1Click:Connect(function()
		ui.mainFrame.Visible = false
		ui.openButton.Visible = true
		ui.openButton.Position = clampGuiPosition(ui.openButton, ui.openButton.Position)
		state.openButtonPosition = ui.openButton.Position
	end)

	disconnectConnection(espObjects.characterConnection)
	espObjects.characterConnection = localPlayer.CharacterAdded:Connect(function(character)
		clearEspInstances()
		character:WaitForChild("HumanoidRootPart", 10)
		if state.espEnabled then
			refreshEspState()
		end
	end)
end

--==================================================
-- Initialization
--==================================================
local loaded, loadMessage = loadConfig()
buildInterface()
connectEvents()
refreshEspState()

if loaded then
	setStatus(loadMessage)
elseif loadMessage == "No config found" then
	setStatus("Ready")
else
	setStatus(loadMessage)
end

if state.savedPosition and state.espEnabled then
	refreshEspState()
end
