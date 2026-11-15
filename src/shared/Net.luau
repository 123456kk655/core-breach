-- The wire between the server simulation and the client renderer.
-- The server creates the remotes and the client waits for them, so a client that
-- joins mid-round still attaches to the same folder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.FOLDER = "CoreBreach"

Net.REMOTES = {
	input = "Input", -- client -> server: held keys, aim direction, trigger
	upgrade = "Upgrade", -- client -> server: the id of the chosen upgrade
	restart = "Restart", -- client -> server: play again
	snapshot = "Snapshot", -- server -> client: the whole round state, every tick
}

-- Called once, on the server, before any player can join.
function Net.initServer()
	local folder = ReplicatedStorage:FindFirstChild(Net.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Net.FOLDER
		folder.Parent = ReplicatedStorage
	end
	for _, name in pairs(Net.REMOTES) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	return folder
end

-- Called on the client: waits for the server's folder to replicate.
function Net.folder()
	local existing = ReplicatedStorage:FindFirstChild(Net.FOLDER)
	if existing then
		return existing
	end
	return ReplicatedStorage:WaitForChild(Net.FOLDER, 30)
end

function Net.remote(name)
	return Net.folder():WaitForChild(name, 30)
end

return Net
