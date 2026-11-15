-- Server entry. Creates the remotes, keeps one simulation per player, and steps
-- every simulation on the server's own clock so the round cannot be driven by a
-- client's idea of time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Sim = require(script:WaitForChild("Sim"))

local MAX_STEP = 0.1

local folder = Net.initServer()
local sessions = {}

local function startRound(player)
	local session = Sim.newRound(player, folder)
	sessions[player] = session
end

local function stopRound(player)
	sessions[player] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
	startRound(player)
end

Players.PlayerAdded:Connect(startRound)
Players.PlayerRemoving:Connect(stopRound)

folder:WaitForChild(Net.REMOTES.input).OnServerEvent:Connect(function(player, payload)
	local session = sessions[player]
	if session then
		session:setInput(payload)
	end
end)

folder:WaitForChild(Net.REMOTES.upgrade).OnServerEvent:Connect(function(player, upgradeId)
	local session = sessions[player]
	if session and type(upgradeId) == "string" then
		session:chooseUpgrade(upgradeId)
	end
end)

folder:WaitForChild(Net.REMOTES.restart).OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if session then
		session:reset()
	end
end)

RunService.Heartbeat:Connect(function(dt)
	local step = math.min(dt, MAX_STEP)
	for _, session in pairs(sessions) do
		session:tick(step)
	end
end)

print("[CORE BREACH] server ready: 5 waves, 5 enemy kinds, 8 modules")
