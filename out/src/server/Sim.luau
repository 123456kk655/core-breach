-- The authoritative game. One Session runs one player's round: it owns the ship,
-- the enemies, the bullets, the wave script and the score, and sends a snapshot to
-- the client so the client never has to guess at state it does not own.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Sim = {}

local SNAPSHOT_HZ = 30
local ARENA = Config.Arena
local ENEMY = Config.Enemies
local WAVE_BONUS = 120

local function length(x, y)
	return math.sqrt(x * x + y * y)
end

local function clamp(value, low, high)
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

-- A deterministic little generator keeps a replay of the same inputs stable, and
-- keeps the sim off the global RNG that other systems also draw from.
local function makeRandom(seed)
	local state = seed % 2147483647
	if state <= 0 then
		state = state + 2147483646
	end
	return function(top)
		state = (state * 16807) % 2147483647
		return ((state - 1) % top) + 1
	end
end

local Session = {}
Session.__index = Session

function Session.new(player, folder)
	local self = setmetatable({}, Session)
	self.player = player
	self.folder = folder
	self.nextId = 1

	local seed = (player.UserId % 100000) + 7919
	self.random = makeRandom(seed)

	self.input = { moveX = 0, moveY = 0, aimX = 1, aimY = 0, firing = false }
	self.snapshotTimer = 0
	self:reset()
	return self
end

function Session:reset()
	self.stats = Config.newStats()
	self.ship = { x = Config.Ship.spawnX, y = Config.Ship.spawnY, angle = 0, radius = Config.Ship.radius }
	self.enemies = {}
	self.bullets = {}
	self.score = 0
	self.kills = 0
	self.wave = 1
	self.phase = "playing" -- playing | upgrade | won | lost
	self.spawnQueue = {}
	self.spawnTimer = 0.9
	self.fireTimer = 0
	self.orbitTimer = 0
	self.invulnerable = 1.2
	self.offers = {}
	self.picked = {}
	self.elapsed = 0
	self:loadWave(1)
end

-- Build the spawn queue for a wave: an explicit, ordered list so the pacing is the
-- one the wave table describes.
function Session:loadWave(index)
	local script_ = Config.Waves[index]
	if not script_ then
		return
	end
	self.wave = index
	self.spawnInterval = script_.spawnInterval
	self.spawnQueue = {}
	for _, group in ipairs(script_.spawns) do
		for _ = 1, group.count do
			table.insert(self.spawnQueue, group.kind)
		end
	end
	self.spawnTimer = 1.0
end

function Session:spawnEnemy(kind)
	local spec = ENEMY[kind]
	if not spec then
		return
	end

	-- Enemies arrive from just outside the arena, so the player sees them come in.
	local edge = self.random(4)
	local pad = spec.radius + 18
	local x, y
	if edge == 1 then
		x, y = self.random(ARENA.width), -pad
	elseif edge == 2 then
		x, y = ARENA.width + pad, self.random(ARENA.height)
	elseif edge == 3 then
		x, y = self.random(ARENA.width), ARENA.height + pad
	else
		x, y = -pad, self.random(ARENA.height)
	end

	local enemy = {
		id = self.nextId,
		kind = kind,
		x = x,
		y = y,
		radius = spec.radius,
		hp = spec.hp,
		maxHp = spec.hp,
		angle = 0,
		fireTimer = spec.fireInterval and (0.6 + math.random()) or nil,
	}
	self.nextId = self.nextId + 1
	table.insert(self.enemies, enemy)
	return enemy
end

function Session:spawnBullet(x, y, angle, speed, radius, damage, life, hitsLeft, fromPlayer)
	table.insert(self.bullets, {
		id = self.nextId,
		x = x,
		y = y,
		vx = math.cos(angle) * speed,
		vy = math.sin(angle) * speed,
		angle = angle,
		radius = radius,
		damage = damage,
		life = life,
		hitsLeft = hitsLeft,
		fromPlayer = fromPlayer,
	})
	self.nextId = self.nextId + 1
end

function Session:firePlayer()
	if self.fireTimer > 0 then
		return
	end
	self.fireTimer = self.stats.fireInterval

	local aim = math.atan2(self.input.aimY, self.input.aimX)
	local shots = self.stats.shots
	local spread = self.stats.spread
	local start = aim - spread * (shots - 1) * 0.5

	for index = 1, shots do
		local angle = start + spread * (index - 1)
		self:spawnBullet(
			self.ship.x + math.cos(angle) * 22,
			self.ship.y + math.sin(angle) * 22,
			angle,
			Config.Ship.bulletSpeed,
			Config.Ship.bulletRadius,
			self.stats.damage,
			Config.Ship.bulletLife,
			self.stats.pierce,
			true
		)
	end
end

-- Orbital turrets: each one circles the ship and picks its own nearest target.
function Session:fireOrbitals(dt)
	if self.stats.orbitals <= 0 then
		return
	end
	self.orbitTimer = self.orbitTimer - dt
	if self.orbitTimer > 0 then
		return
	end
	self.orbitTimer = 0.55

	for index = 1, self.stats.orbitals do
		local orbitAngle = self.elapsed * 1.6 + (index - 1) * (math.pi * 2 / self.stats.orbitals)
		local ox = self.ship.x + math.cos(orbitAngle) * 46
		local oy = self.ship.y + math.sin(orbitAngle) * 46

		local target, best = nil, math.huge
		for _, enemy in ipairs(self.enemies) do
			local dist = length(enemy.x - ox, enemy.y - oy)
			if dist < best then
				best, target = dist, enemy
			end
		end
		if target then
			local angle = math.atan2(target.y - oy, target.x - ox)
			self:spawnBullet(ox, oy, angle, Config.Ship.bulletSpeed * 0.9, 4, self.stats.damage * 0.7, 0.9, 0, true)
		end
	end
end

function Session:damageShip(amount)
	if self.invulnerable > 0 or self.phase ~= "playing" then
		return
	end
	self.stats.hp = self.stats.hp - amount
	self.invulnerable = Config.Ship.invulnerableFor
	if self.stats.hp <= 0 then
		self.stats.hp = 0
		self.phase = "lost"
	end
end

function Session:stepEnemies(dt)
	for index = #self.enemies, 1, -1 do
		local enemy = self.enemies[index]
		local spec = ENEMY[enemy.kind]
		local dx = self.ship.x - enemy.x
		local dy = self.ship.y - enemy.y
		local dist = length(dx, dy)
		if dist < 0.001 then
			dx, dy, dist = 1, 0, 1
		end
		enemy.angle = math.atan2(dy, dx)

		-- Shooting kinds keep their distance; melee kinds walk into the ship.
		local desired = spec.fireInterval and 330 or 0
		local speed = spec.speed
		if dist > desired + 20 then
			enemy.x = enemy.x + (dx / dist) * speed * dt
			enemy.y = enemy.y + (dy / dist) * speed * dt
		elseif dist < desired - 40 then
			enemy.x = enemy.x - (dx / dist) * speed * dt * 0.7
			enemy.y = enemy.y - (dy / dist) * speed * dt * 0.7
		end

		if enemy.fireTimer then
			enemy.fireTimer = enemy.fireTimer - dt
			if enemy.fireTimer <= 0 and dist < 900 then
				enemy.fireTimer = spec.fireInterval
				if enemy.kind == "boss" then
					-- The boss answers in a fan so the player has to move through it.
					for spreadIndex = -2, 2 do
						self:spawnBullet(
							enemy.x,
							enemy.y,
							enemy.angle + spreadIndex * 0.22,
							Config.Bullet.enemySpeed,
							Config.Bullet.enemyRadius,
							Config.Bullet.enemyDamage,
							Config.Bullet.enemyLife,
							0,
							false
						)
					end
				else
					self:spawnBullet(
						enemy.x,
						enemy.y,
						enemy.angle,
						Config.Bullet.enemySpeed,
						Config.Bullet.enemyRadius,
						Config.Bullet.enemyDamage,
						Config.Bullet.enemyLife,
						0,
						false
					)
				end
			end
		end

		-- Contact damage.
		if dist < enemy.radius + self.ship.radius then
			self:damageShip(spec.contact)
			enemy.x = enemy.x - (dx / dist) * 26
			enemy.y = enemy.y - (dy / dist) * 26
		end

		if enemy.hp <= 0 then
			table.remove(self.enemies, index)
			self.kills = self.kills + 1
			self.score = self.score + spec.score
		end
	end
end

function Session:stepBullets(dt)
	for index = #self.bullets, 1, -1 do
		local bullet = self.bullets[index]
		bullet.x = bullet.x + bullet.vx * dt
		bullet.y = bullet.y + bullet.vy * dt
		bullet.life = bullet.life - dt

		local dead = bullet.life <= 0

		if not dead then
			if bullet.fromPlayer then
				for enemyIndex = #self.enemies, 1, -1 do
					local enemy = self.enemies[enemyIndex]
					if enemy.hp > 0 and length(enemy.x - bullet.x, enemy.y - bullet.y) < enemy.radius + bullet.radius then
						enemy.hp = enemy.hp - bullet.damage
						enemy.flash = 0.12
						if bullet.hitsLeft > 0 then
							bullet.hitsLeft = bullet.hitsLeft - 1
							bullet.damage = bullet.damage * 0.85
						else
							dead = true
						end
						break
					end
				end
			elseif self.phase == "playing" and length(self.ship.x - bullet.x, self.ship.y - bullet.y) < self.ship.radius + bullet.radius then
				self:damageShip(bullet.damage)
				dead = true
			end
		end

		if not dead and (bullet.x < -80 or bullet.x > ARENA.width + 80 or bullet.y < -80 or bullet.y > ARENA.height + 80) then
			dead = true
		end

		if dead then
			table.remove(self.bullets, index)
		end
	end
end

function Session:step(dt)
	if self.phase == "won" or self.phase == "lost" then
		self.snapshotTimer = self.snapshotTimer - dt
		return
	end

	self.elapsed = self.elapsed + dt
	if self.invulnerable > 0 then
		self.invulnerable = self.invulnerable - dt
	end

	-- Movement, driven only by what the client last reported.
	local moveX, moveY = self.input.moveX, self.input.moveY
	local magnitude = length(moveX, moveY)
	if magnitude > 0.01 then
		if magnitude > 1 then
			moveX, moveY, magnitude = moveX / magnitude, moveY / magnitude, 1
		end
		self.ship.x = clamp(self.ship.x + moveX * self.stats.speed * dt, ARENA.padding, ARENA.width - ARENA.padding)
		self.ship.y = clamp(self.ship.y + moveY * self.stats.speed * dt, ARENA.padding, ARENA.height - ARENA.padding)
		self.ship.angle = math.atan2(moveY, moveX)
	end

	if self.phase == "playing" then
		self.fireTimer = math.max(0, self.fireTimer - dt)
		if self.input.firing then
			self:firePlayer()
		end
		self:fireOrbitals(dt)
		self:stepEnemies(dt)
		self:stepBullets(dt)

		-- Wave pacing: release the queue one enemy at a time, then wait it out.
		if #self.spawnQueue > 0 then
			self.spawnTimer = self.spawnTimer - dt
			if self.spawnTimer <= 0 then
				self:spawnEnemy(table.remove(self.spawnQueue, 1))
				self.spawnTimer = self.spawnInterval
			end
		elseif #self.enemies == 0 then
			self.score = self.score + WAVE_BONUS * self.wave
			if self.wave >= Config.MaxWave then
				self.phase = "won"
			else
				self.phase = "upgrade"
				self:rollOffers()
			end
		end
	end
end

function Session:rollOffers()
	local pool = {}
	for _, upgrade in ipairs(Config.Upgrades) do
		local taken = false
		for _, pickedId in ipairs(self.picked) do
			if pickedId == upgrade.id and upgrade.id ~= "repair" then
				taken = true
				break
			end
		end
		if not taken then
			table.insert(pool, upgrade)
		end
	end

	self.offers = {}
	for _ = 1, math.min(3, #pool) do
		local index = self.random(#pool)
		table.insert(self.offers, table.remove(pool, index).id)
	end
end

function Session:chooseUpgrade(id)
	if self.phase ~= "upgrade" then
		return false
	end
	for _, offerId in ipairs(self.offers) do
		if offerId == id then
			for _, upgrade in ipairs(Config.Upgrades) do
				if upgrade.id == id then
					upgrade.apply(self.stats)
					table.insert(self.picked, id)
					break
				end
			end
			self.offers = {}
			self.wave = self.wave + 1
			self.phase = "playing"
			self:loadWave(self.wave)
			return true
		end
	end
	return false
end

function Session:snapshot()
	local enemies = table.create(#self.enemies)
	for _, enemy in ipairs(self.enemies) do
		table.insert(enemies, {
			id = enemy.id,
			kind = enemy.kind,
			x = enemy.x,
			y = enemy.y,
			r = enemy.radius,
			hp = enemy.hp,
			maxHp = enemy.maxHp,
			flash = enemy.flash or 0,
		})
	end

	local bullets = table.create(#self.bullets)
	for _, bullet in ipairs(self.bullets) do
		table.insert(bullets, {
			id = bullet.id,
			x = bullet.x,
			y = bullet.y,
			a = bullet.angle,
			r = bullet.radius,
			enemy = not bullet.fromPlayer,
		})
	end

	local offers = {}
	for index, id in ipairs(self.offers) do
		offers[index] = id
	end

	return {
		phase = self.phase,
		wave = self.wave,
		waveLabel = Config.Waves[self.wave] and Config.Waves[self.wave].label or "",
		maxWave = Config.MaxWave,
		score = self.score,
		kills = self.kills,
		hp = self.stats.hp,
		maxHp = self.stats.maxHp,
		ship = { x = self.ship.x, y = self.ship.y, a = self.ship.angle, inv = self.invulnerable },
		enemies = enemies,
		bullets = bullets,
		offers = offers,
		orbitals = self.stats.orbitals,
		remaining = #self.enemies + #self.spawnQueue,
		elapsed = self.elapsed,
	}
end

function Session:tick(dt)
	self:step(dt)

	-- Hit flashes are cosmetic, but they decay on the simulation clock so a client
	-- that renders late still shows the hit at the same moment the server applied it.
	for _, enemy in ipairs(self.enemies) do
		if enemy.flash then
			enemy.flash = math.max(0, enemy.flash - dt)
		end
	end

	self.snapshotTimer = self.snapshotTimer - dt
	if self.snapshotTimer <= 0 then
		self.snapshotTimer = 1 / SNAPSHOT_HZ
		local remote = self.folder:FindFirstChild(Net.REMOTES.snapshot)
		if remote then
			remote:FireClient(self.player, self:snapshot())
		end
	end
end

-- Input from the client is treated as a suggestion: ranges are clamped here rather
-- than trusted, so a bad or hostile client cannot move a ship faster than it should.
function Session:setInput(payload)
	if type(payload) ~= "table" then
		return
	end
	local moveX = tonumber(payload.moveX) or 0
	local moveY = tonumber(payload.moveY) or 0
	local aimX = tonumber(payload.aimX) or 1
	local aimY = tonumber(payload.aimY) or 0
	self.input.moveX = clamp(moveX, -1, 1)
	self.input.moveY = clamp(moveY, -1, 1)
	if length(aimX, aimY) > 0.01 then
		self.input.aimX = aimX
		self.input.aimY = aimY
	end
	self.input.firing = payload.firing == true
end

Sim.Session = Session

function Sim.newRound(player, folder)
	return Session.new(player, folder)
end

return Sim
