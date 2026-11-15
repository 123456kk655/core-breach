-- Draws the entities the server snapshot names onto the arena: the ship, the
-- enemies, the bullets and the arena itself. Frames are pooled by id, so a snapshot
-- at 30 Hz updates the frames that are already there instead of rebuilding the board.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local P = Config.Palette
local ARENA = Config.Arena

local Board = {}
Board.__index = Board

local GRID_COLUMNS = 16
local GRID_ROWS = 9
local STAR_COUNT = 54

local function scaleX(units)
	return units / ARENA.width
end

local function scaleY(units)
	return units / ARENA.height
end

local function newFrame(props)
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = P.cyan
	for key, value in pairs(props) do
		frame[key] = value
	end
	return frame
end

local function newStroke(parent, thickness, color)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Board.new(parent)
	local self = setmetatable({}, Board)
	self.parent = parent
	self.enemyFrames = {}
	self.bulletFrames = {}

	self:drawBackdrop()
	self:drawGrid()
	self:drawShip()
	return self
end

function Board:drawBackdrop()
	local glow = newFrame({
		Name = "ArenaGlow",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = P.panel,
		Parent = self.parent,
	})
	glow.ZIndex = 1

	-- A shallow sweep of light across the field, so the arena never reads as flat.
	local sweep = newFrame({
		Name = "Sweep",
		Size = UDim2.fromScale(1, 1),
		Parent = glow,
	})
	sweep.ZIndex = 2
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 40, 70)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(8, 14, 26)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 26, 44)),
	})
	gradient.Rotation = 118
	gradient.Parent = sweep

	-- A fixed starfield: generated once with a fixed seed so every run of the game
	-- shows the same sky.
	local seed = 20261115
	local function rnd()
		seed = (seed * 16807) % 2147483647
		return (seed - 1) / 2147483646
	end
	for index = 1, STAR_COUNT do
		local size = 1.6 + rnd() * 1.8
		local star = newFrame({
			Name = "Star" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(rnd(), rnd()),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = index % 5 == 0 and P.cyan or P.textDim,
			BackgroundTransparency = 0.35 + rnd() * 0.4,
			Parent = glow,
		})
		star.ZIndex = 3
	end
end

function Board:drawGrid()
	local grid = newFrame({
		Name = "Grid",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = self.parent,
	})
	grid.ZIndex = 4

	for column = 1, GRID_COLUMNS - 1 do
		local line = newFrame({
			Name = "V" .. column,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(column / GRID_COLUMNS, 0.5),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = P.grid,
			BackgroundTransparency = 0.55,
			Parent = grid,
		})
		line.ZIndex = 4
	end

	for row = 1, GRID_ROWS - 1 do
		local line = newFrame({
			Name = "H" .. row,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, row / GRID_ROWS),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = P.grid,
			BackgroundTransparency = 0.55,
			Parent = grid,
		})
		line.ZIndex = 4
	end
end

function Board:drawShip()
	local holder = newFrame({
		Name = "Ship",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = self.parent,
	})
	holder.ZIndex = 20

	local halo = newFrame({
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.9, 1.9),
		BackgroundColor3 = P.cyan,
		BackgroundTransparency = 0.86,
		Parent = holder,
	})
	halo.ZIndex = 11
	local haloCorner = Instance.new("UICorner")
	haloCorner.CornerRadius = UDim.new(1, 0)
	haloCorner.Parent = halo

	local body = newFrame({
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = P.cyan,
		Rotation = 45,
		Parent = holder,
	})
	body.ZIndex = 13
	local bodyCorner = Instance.new("UICorner")
	bodyCorner.CornerRadius = UDim.new(0, 7)
	bodyCorner.Parent = body
	newStroke(body, 2, P.white)

	local core = newFrame({
		Name = "Core",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.42, 0.42),
		BackgroundColor3 = P.white,
		Parent = body,
	})
	core.ZIndex = 14
	local coreCorner = Instance.new("UICorner")
	coreCorner.CornerRadius = UDim.new(0, 3)
	coreCorner.Parent = core

	-- The aiming line tells the player where the next bullet will go.
	local aim = newFrame({
		Name = "Aim",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(2.4, 0.14),
		BackgroundColor3 = P.white,
		BackgroundTransparency = 0.55,
		Parent = holder,
	})
	aim.ZIndex = 12
	local aimCorner = Instance.new("UICorner")
	aimCorner.CornerRadius = UDim.new(1, 0)
	aimCorner.Parent = aim

	self.shipHolder = holder
	self.shipAim = aim
	self.shipHalo = halo
end

local function styleEnemyFrame(frame, spec)
	local corner = Instance.new("UICorner")
	local color = P[spec.color]

	if spec.shape == "ring" then
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 0.82
		corner.CornerRadius = UDim.new(1, 0)
		newStroke(frame, 3, color)
	elseif spec.shape == "square" then
		frame.BackgroundColor3 = color
		corner.CornerRadius = UDim.new(0, 4)
		newStroke(frame, 3, P.white)
	elseif spec.shape == "dart" then
		frame.BackgroundColor3 = color
		corner.CornerRadius = UDim.new(0, 5)
		newStroke(frame, 1.5, P.white)
	elseif spec.shape == "boss" then
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 0.25
		corner.CornerRadius = UDim.new(1, 0)
		newStroke(frame, 5, P.white)
	else
		frame.BackgroundColor3 = color
		corner.CornerRadius = UDim.new(0, 6)
		newStroke(frame, 2, P.white)
	end

	corner.Parent = frame
	return color
end

function Board:enemyFrame(enemy)
	local existing = self.enemyFrames[enemy.id]
	if existing then
		return existing
	end

	local spec = Config.Enemies[enemy.kind] or Config.Enemies.drone
	local holder = newFrame({
		Name = "Enemy" .. enemy.id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = self.parent,
	})
	holder.ZIndex = 15

	local width = enemy.r * 2
	local height = enemy.r * 2
	if spec.shape == "dart" then
		width = enemy.r * 2.6
		height = enemy.r * 1.5
	end

	local body = newFrame({
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(scaleX(width), scaleY(height)),
		Parent = holder,
	})
	body.ZIndex = 16
	local color = styleEnemyFrame(body, spec)

	-- The boss carries a health bar so the last wave reads as a fight with a goal.
	local bar
	if spec.shape == "boss" then
		bar = newFrame({
			Name = "HpBar",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, -0.08),
			Size = UDim2.fromScale(1.5, 0.09),
			BackgroundColor3 = P.panelEdge,
			Parent = holder,
		})
		bar.ZIndex = 18
		local fill = newFrame({
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = P.danger,
			Parent = bar,
		})
		fill.ZIndex = 19
		newStroke(bar, 1.5, P.white)
		bar:SetAttribute("Fill", true)
	end

	-- Darts and the boss face the way they travel.
	holder:SetAttribute("Kind", enemy.kind)
	self.enemyFrames[enemy.id] = {
		holder = holder,
		body = body,
		bar = bar,
		color = color,
		kind = enemy.kind,
	}
	return self.enemyFrames[enemy.id]
end

function Board:bulletFrame(bullet)
	local existing = self.bulletFrames[bullet.id]
	if existing then
		return existing
	end

	local frame
	if bullet.enemy then
		frame = newFrame({
			Name = "EBullet" .. bullet.id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = P.magenta,
			Parent = self.parent,
		})
		frame.Size = UDim2.fromScale(scaleX(bullet.r * 2.2), scaleY(bullet.r * 2.2))
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame
		newStroke(frame, 2, P.white)
		frame.ZIndex = 17
	else
		frame = newFrame({
			Name = "PBullet" .. bullet.id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = P.cyan,
			Parent = self.parent,
		})
		frame.Size = UDim2.fromScale(scaleX(22), scaleY(6))
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame
		newStroke(frame, 1.5, P.white)
		frame.ZIndex = 17
	end

	local halo = newFrame({
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(2.4, 2.4),
		BackgroundColor3 = bullet.enemy and P.magenta or P.cyan,
		BackgroundTransparency = 0.8,
		Parent = frame,
	})
	halo.ZIndex = 16
	local haloCorner = Instance.new("UICorner")
	haloCorner.CornerRadius = UDim.new(1, 0)
	haloCorner.Parent = halo

	self.bulletFrames[bullet.id] = frame
	return frame
end

function Board:render(snapshot, aimX, aimY)
	-- Ship.
	local ship = snapshot.ship
	local holder = self.shipHolder
	holder.Position = UDim2.fromScale(scaleX(ship.x), scaleY(ship.y))
	holder.Size = UDim2.fromScale(scaleX(Config.Ship.radius * 2), scaleY(Config.Ship.radius * 2))

	local aimAngle = math.atan2(aimY, aimX)
	self.shipAim.Rotation = math.deg(aimAngle)

	-- Blink while invulnerable so a hit is legible.
	if snapshot.phase == "playing" and ship.inv > 0 then
		holder.Visible = (math.floor(ship.inv * 18) % 2) == 0
	else
		holder.Visible = true
	end

	-- Enemies: update the frames the snapshot names, drop the ones it does not.
	local seen = {}
	for _, enemy in ipairs(snapshot.enemies) do
		seen[enemy.id] = true
		local entry = self:enemyFrame(enemy)
		entry.holder.Position = UDim2.fromScale(scaleX(enemy.x), scaleY(enemy.y))
		if entry.kind == "dart" then
			entry.holder.Rotation = 0
			entry.body.Rotation = math.deg(math.atan2(snapshot.ship.y - enemy.y, snapshot.ship.x - enemy.x))
		end
		if enemy.flash > 0 then
			entry.body.BackgroundColor3 = P.white
		else
			entry.body.BackgroundColor3 = entry.color
		end
		if entry.bar then
			local fill = entry.bar:FindFirstChild("Fill")
			if fill then
				fill.Size = UDim2.fromScale(math.clamp(enemy.hp / enemy.maxHp, 0, 1), 1)
			end
		end
	end
	for id, entry in pairs(self.enemyFrames) do
		if not seen[id] then
			entry.holder:Destroy()
			self.enemyFrames[id] = nil
		end
	end

	-- Bullets.
	local liveBullets = {}
	for _, bullet in ipairs(snapshot.bullets) do
		liveBullets[bullet.id] = true
		local frame = self:bulletFrame(bullet)
		frame.Position = UDim2.fromScale(scaleX(bullet.x), scaleY(bullet.y))
		frame.Rotation = math.deg(bullet.a)
	end
	for id, frame in pairs(self.bulletFrames) do
		if not liveBullets[id] then
			frame:Destroy()
			self.bulletFrames[id] = nil
		end
	end

	-- Orbital turrets, drawn from the count the server reports.
	for index = 1, snapshot.orbitals do
		local key = "Orbital" .. index
		local orbital = self.orbitals and self.orbitals[key]
		if not orbital then
			orbital = newFrame({
				Name = key,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromScale(scaleX(13), scaleY(13)),
				BackgroundColor3 = P.green,
				Parent = self.parent,
			})
			orbital.ZIndex = 18
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = orbital
			newStroke(orbital, 1.5, P.white)
			self.orbitals = self.orbitals or {}
			self.orbitals[key] = orbital
		end
		local angle = snapshot.elapsed * 1.6 + (index - 1) * (math.pi * 2 / math.max(1, snapshot.orbitals))
		orbital.Position = UDim2.fromScale(
			scaleX(ship.x + math.cos(angle) * 46),
			scaleY(ship.y + math.sin(angle) * 46)
		)
		orbital.Visible = snapshot.phase == "playing"
	end
	if self.orbitals then
		for key, orbital in pairs(self.orbitals) do
			local index = tonumber(key:match("%d+") or "0") or 0
			if index > snapshot.orbitals then
				orbital:Destroy()
				self.orbitals[key] = nil
			end
		end
	end
end

function Board:shake(intensity)
	-- The arena is nudged, never moved: the shake always settles back to zero.
	self.shakeLeft = (self.shakeLeft or 0) + intensity
end

function Board:step(dt)
	if not self.shakeLeft or self.shakeLeft <= 0 then
		if self.parent.Position ~= UDim2.fromScale(0.5, 0.5) then
			self.parent.Position = UDim2.fromScale(0.5, 0.5)
		end
		return
	end
	self.shakeLeft = math.max(0, self.shakeLeft - dt * 3)
	local magnitude = self.shakeLeft * 5
	self.parent.Position = UDim2.new(
		0.5,
		math.sin(os.clock() * 62) * magnitude,
		0.5,
		math.cos(os.clock() * 48) * magnitude
	)
end

return Board
