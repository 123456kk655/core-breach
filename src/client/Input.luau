-- Reads the keyboard and mouse and turns them into one small payload the server
-- understands. Aim is reported as a direction in design units, so the server never
-- has to know the player's screen size.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Input = {}
Input.__index = Input

local MOVE_KEYS = {
	[Enum.KeyCode.W] = { 0, -1 },
	[Enum.KeyCode.Up] = { 0, -1 },
	[Enum.KeyCode.S] = { 0, 1 },
	[Enum.KeyCode.Down] = { 0, 1 },
	[Enum.KeyCode.A] = { -1, 0 },
	[Enum.KeyCode.Left] = { -1, 0 },
	[Enum.KeyCode.D] = { 1, 0 },
	[Enum.KeyCode.Right] = { 1, 0 },
}

function Input.new(arena, callbacks)
	local self = setmetatable({}, Input)
	self.arena = arena
	self.callbacks = callbacks or {}
	self.pointerDown = false
	self.spaceDown = false
	self.aimX = 1
	self.aimY = 1

	self.connections = {}

	local function track(connection)
		table.insert(self.connections, connection)
	end

	track(UserInputService.InputBegan:Connect(function(inputObject, processed)
		if processed then
			if inputObject.KeyCode == Enum.KeyCode.R then
				-- Restart stays live even while a GUI element has focus.
				if self.callbacks.onRestart then
					self.callbacks.onRestart()
				end
			end
			return
		end
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
			self.pointerDown = true
		elseif inputObject.KeyCode == Enum.KeyCode.Space then
			self.spaceDown = true
		elseif inputObject.KeyCode == Enum.KeyCode.R then
			if self.callbacks.onRestart then
				self.callbacks.onRestart()
			end
		end

		-- Number keys pick an upgrade card when one is offered.
		local number = inputObject.KeyCode.Value - Enum.KeyCode.One.Value + 1
		if number >= 1 and number <= 3 then
			if self.callbacks.onUpgradeKey then
				self.callbacks.onUpgradeKey(number)
			end
		end
	end)

	track(UserInputService.InputEnded:Connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
			self.pointerDown = false
		elseif inputObject.KeyCode == Enum.KeyCode.Space then
			self.spaceDown = false
		end
	end)

	-- A window that loses focus must not leave the ship firing forever.
	track(UserInputService.WindowFocusReleased:Connect(function()
		self.pointerDown = false
		self.spaceDown = false
	end))

	return self
end

function Input:sample()
	local moveX, moveY = 0, 0
	for keyCode, direction in pairs(MOVE_KEYS) do
		if UserInputService:IsKeyDown(keyCode) then
			moveX = moveX + direction[1]
			moveY = moveY + direction[2]
		end
	end

	-- Aim: the mouse relative to the middle of the arena, in design units.
	local mouse = UserInputService:GetMouseLocation()
	local origin = self.arena.AbsolutePosition
	local size = self.arena.AbsoluteSize
	if size.X > 0 and size.Y > 0 then
		local relX = (mouse.X - origin.X) / size.X - 0.5
		local relY = (mouse.Y - origin.Y) / size.Y - 0.5
		self.aimX = relX * Config.Arena.width
		self.aimY = relY * Config.Arena.height
	end

	return {
		moveX = moveX,
		moveY = moveY,
		aimX = self.aimX,
		aimY = self.aimY,
		firing = self.pointerDown or self.spaceDown,
	}
end

function Input:aim()
	return self.aimX, self.aimY
end

function Input:destroy()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
end

return Input
