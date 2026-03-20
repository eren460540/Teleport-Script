-- LocalScript: Draggable teleport menu GUI for the local player.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local savedPosition = nil

-- Create the root ScreenGui.
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TeleportMenu"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Helper to add rounded corners to UI objects.
local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 8)
	corner.Parent = instance
	return corner
end

-- Create the open menu button.
local openButton = Instance.new("TextButton")
openButton.Name = "OpenButton"
openButton.Size = UDim2.new(0, 140, 0, 44)
openButton.Position = UDim2.new(0, 20, 0.5, -22)
openButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextSize = 18
openButton.Font = Enum.Font.GothamBold
openButton.Text = "Open Menu"
openButton.Parent = screenGui
addCorner(openButton)

-- Create the main menu frame.
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 300, 0, 200)
mainFrame.Position = UDim2.new(0.5, -150, 0.5, -100)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
addCorner(mainFrame, UDim.new(0, 10))

-- Create the title bar.
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
titleBar.BorderSizePixel = 0
titleBar.Active = true
titleBar.Parent = mainFrame
addCorner(titleBar, UDim.new(0, 10))

-- Cover the lower title bar corners so only the top corners appear rounded.
local titleBarFill = Instance.new("Frame")
titleBarFill.Name = "TitleBarFill"
titleBarFill.Size = UDim2.new(1, 0, 0, 20)
titleBarFill.Position = UDim2.new(0, 0, 0, 20)
titleBarFill.BackgroundColor3 = titleBar.BackgroundColor3
titleBarFill.BorderSizePixel = 0
titleBarFill.Parent = titleBar

-- Add the title text.
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, -50, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Teleport Menu"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 18
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = titleBar

-- Add the close button.
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.Position = UDim2.new(1, -36, 0, 5)
closeButton.BackgroundColor3 = Color3.fromRGB(170, 60, 60)
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextSize = 16
closeButton.Font = Enum.Font.GothamBold
closeButton.Text = "X"
closeButton.Parent = titleBar
addCorner(closeButton, UDim.new(0, 6))

-- Add the status label.
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, -20, 0, 28)
statusLabel.Position = UDim2.new(0, 10, 0, 55)
statusLabel.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.TextSize = 16
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = "Ready"
statusLabel.Parent = mainFrame
addCorner(statusLabel)

-- Add the Set Position button.
local setPositionButton = Instance.new("TextButton")
setPositionButton.Name = "SetPositionButton"
setPositionButton.Size = UDim2.new(1, -20, 0, 44)
setPositionButton.Position = UDim2.new(0, 10, 0, 100)
setPositionButton.BackgroundColor3 = Color3.fromRGB(70, 110, 200)
setPositionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
setPositionButton.TextSize = 18
setPositionButton.Font = Enum.Font.GothamBold
setPositionButton.Text = "Set Position"
setPositionButton.Parent = mainFrame
addCorner(setPositionButton)

-- Add the teleport button.
local teleportButton = Instance.new("TextButton")
teleportButton.Name = "TeleportButton"
teleportButton.Size = UDim2.new(1, -20, 0, 44)
teleportButton.Position = UDim2.new(0, 10, 0, 150)
teleportButton.BackgroundColor3 = Color3.fromRGB(70, 170, 110)
teleportButton.TextColor3 = Color3.fromRGB(255, 255, 255)
teleportButton.TextSize = 18
teleportButton.Font = Enum.Font.GothamBold
teleportButton.Text = "TP to Position"
teleportButton.Parent = mainFrame
addCorner(teleportButton)

-- Track drag state for draggable UI elements.
local dragging = false
local dragInput = nil
local dragStart = nil
local startPosition = nil
local dragTarget = nil

-- Shared drag starter for frames and buttons.
local function beginDrag(input, target)
	dragging = true
	dragInput = input
	dragStart = input.Position
	startPosition = target.Position
	dragTarget = target

	input.Changed:Connect(function()
		if input.UserInputState == Enum.UserInputState.End then
			dragging = false
			dragInput = nil
			dragTarget = nil
		end
	end)
end

-- Make a GUI object draggable with mouse or touch input.
local function makeDraggable(handle, target)
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input, target)
		end
	end)

	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
end

-- Update the dragged UI object's position as the pointer moves.
UserInputService.InputChanged:Connect(function(input)
	if dragging and dragTarget and input == dragInput then
		local delta = input.Position - dragStart
		dragTarget.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end
end)

-- Helper to get the local player's HumanoidRootPart.
local function getHumanoidRootPart()
	local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
	return character:WaitForChild("HumanoidRootPart")
end

-- Save the current position.
setPositionButton.MouseButton1Click:Connect(function()
	local humanoidRootPart = getHumanoidRootPart()
	savedPosition = humanoidRootPart.CFrame
	statusLabel.Text = "Position saved"
end)

-- Teleport back to the saved position.
teleportButton.MouseButton1Click:Connect(function()
	if savedPosition then
		local humanoidRootPart = getHumanoidRootPart()
		humanoidRootPart.CFrame = savedPosition
		statusLabel.Text = "Teleported to saved position"
	else
		statusLabel.Text = "No position saved"
	end
end)

-- Show the full menu and hide the open button.
openButton.MouseButton1Click:Connect(function()
	mainFrame.Visible = true
	openButton.Visible = false
end)

-- Hide the full menu and show the open button.
closeButton.MouseButton1Click:Connect(function()
	mainFrame.Visible = false
	openButton.Visible = true
end)

-- Enable dragging on the title bar and open button.
makeDraggable(titleBar, mainFrame)
makeDraggable(openButton, openButton)
