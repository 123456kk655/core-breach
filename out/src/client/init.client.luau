-- Client entry. Builds the screen, owns the render loop, and keeps the network
-- traffic to one direction each way: input out, snapshots in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Board = require(script:WaitForChild("Board"))
local Hud = require(script:WaitForChild("Hud"))
local Input = require(script:WaitForChild("Input"))

local P = Config.Palette
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INPUT_HZ = 30
local lastWave = 0

-- The whole game is drawn in one ScreenGui, so the field, the HUD and the overlays
-- stay together at any resolution.
local screen = Instance.new("ScreenGui")
screen.Name = "CoreBreach"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 20
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = P.backdrop
backdrop.BorderSizePixel = 0
backdrop.ZIndex = 1
backdrop.Parent = screen

-- A soft frame around the field, drawn behind the arena.
local vignette = Instance.new("Frame")
vignette.Name = "Vignette"
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundTransparency = 1
vignette.ZIndex = 2
vignette.Parent = backdrop
local vignetteGradient = Instance.new("UIGradient")
vignetteGradient.Rotation = 90
vignetteGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 16, 28)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(6, 9, 18)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(2, 4, 9)),
})
vignetteGradient.Parent = vignette

local arena = Instance.new("Frame")
arena.Name = "Arena"
arena.AnchorPoint = Vector2.new(0.5, 0.5)
arena.Position = UDim2.fromScale(0.5, 0.5)
arena.Size = UDim2.fromScale(0.9, 0.9)
arena.BackgroundColor3 = P.panel
arena.BorderSizePixel = 0
arena.ClipsDescendants = true
arena.ZIndex = 10
arena.Parent = screen

local arenaCorner = Instance.new("UICorner")
arenaCorner.CornerRadius = UDim.new(0, 14)
arenaCorner.Parent = arena

local arenaStroke = Instance.new("UIStroke")
arenaStroke.Thickness = 2
arenaStroke.Color = P.panelEdge
arenaStroke.Parent = arena

local arenaAspect = Instance.new("UIAspectRatioConstraint")
arenaAspect.AspectRatio = Config.Arena.width / Config.Arena.height
arenaAspect.AspectType = Enum.AspectType.FitInWithMaximumSize
arenaAspect.DominantAxis = Enum.DominantAxis.Width
arenaAspect.Parent = arena

local upgradesRemote = Net.remote(Net.REMOTES.upgrade)
local inputRemote = Net.remote(Net.REMOTES.input)
local restartRemote = Net.remote(Net.REMOTES.restart)
local snapshotRemote = Net.remote(Net.REMOTES.snapshot)

local board = Board.new(arena)
local hud = Hud.new(screen, function(id)
	upgradesRemote:FireServer(id)
end)
local input = Input.new(arena, {
	onUpgradeKey = function(index)
		hud:choose(index)
	end,
	onRestart = function()
		restartRemote:FireServer()
		hud:resetRound()
	end,
})

local sendTimer = 0
local lastHp = nil

RunService.RenderStepped:Connect(function(dt)
	local payload = input:sample()

	-- Input goes out at a fixed rate rather than every frame: the simulation needs a
	-- steady stream, not a flood.
	sendTimer = sendTimer + dt
	if sendTimer >= 1 / INPUT_HZ then
		sendTimer = 0
		inputRemote:FireServer(payload)
	end

	board:step(dt)
	hud:step(dt)
end)

snapshotRemote.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.ship) ~= "table" then
		return
	end

	local aimX, aimY = input:aim()
	board:render(snapshot, aimX, aimY)
	hud:update(snapshot)

	-- A wave that has just started gets its name called out.
	if snapshot.phase == "playing" and snapshot.wave ~= lastWave then
		lastWave = snapshot.wave
		if snapshot.wave > 1 then
			hud:showWaveBanner("WAVE " .. snapshot.wave .. "  ·  " .. (snapshot.waveLabel or ""))
		end
	end
	if snapshot.phase ~= "playing" then
		lastWave = snapshot.wave
	end

	-- Taking damage is felt, not just read.
	if lastHp and snapshot.hp < lastHp then
		board:shake(1)
	end
	lastHp = snapshot.hp
end)

-- The player never spawns a character: the game is drawn, not walked around.
player.CameraMode = Enum.CameraMode.Classic
UserInputService.MouseIconEnabled = true
