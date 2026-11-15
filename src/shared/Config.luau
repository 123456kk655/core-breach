-- Shared configuration and content for CORE BREACH.
-- Every number the game balances on lives here, so the server simulation and the
-- client's renderers read the same values and a screenshot always matches the code.

local Config = {}

-- The play field is measured in design units; the client maps it onto the screen.
Config.Arena = {
	width = 1600,
	height = 900,
	padding = 30,
}

Config.Ship = {
	radius = 17,
	speed = 430,
	maxHp = 100,
	fireInterval = 0.30,
	damage = 13,
	bulletSpeed = 1000,
	bulletRadius = 5,
	bulletLife = 1.1,
	invulnerableFor = 0.65,
	spawnX = 800,
	spawnY = 620,
}

Config.Bullet = {
	enemySpeed = 320,
	enemyRadius = 7,
	enemyLife = 4.0,
	enemyDamage = 10,
}

-- One palette, used by both the HUD and the arena so the game reads as one object.
Config.Palette = {
	backdrop = Color3.fromRGB(6, 9, 18),
	panel = Color3.fromRGB(13, 20, 33),
	panelEdge = Color3.fromRGB(30, 48, 76),
	grid = Color3.fromRGB(22, 44, 70),
	cyan = Color3.fromRGB(56, 232, 255),
	cyanDim = Color3.fromRGB(24, 118, 138),
	magenta = Color3.fromRGB(255, 61, 138),
	amber = Color3.fromRGB(255, 194, 75),
	violet = Color3.fromRGB(168, 118, 255),
	danger = Color3.fromRGB(255, 77, 94),
	text = Color3.fromRGB(232, 244, 255),
	textDim = Color3.fromRGB(127, 151, 184),
	white = Color3.fromRGB(255, 255, 255),
	green = Color3.fromRGB(92, 240, 168),
}

-- Enemy kinds. `shape` and `color` are what the client draws; everything else is
-- what the server simulates.
Config.Enemies = {
	drone = {
		radius = 20,
		speed = 104,
		hp = 34,
		contact = 12,
		score = 10,
		shape = "diamond",
		color = "amber",
	},
	dart = {
		radius = 14,
		speed = 232,
		hp = 16,
		contact = 8,
		score = 12,
		shape = "dart",
		color = "magenta",
	},
	brute = {
		radius = 31,
		speed = 66,
		hp = 96,
		contact = 22,
		score = 25,
		shape = "square",
		color = "violet",
	},
	turret = {
		radius = 23,
		speed = 44,
		hp = 58,
		contact = 10,
		score = 20,
		shape = "ring",
		color = "danger",
		fireInterval = 2.1,
	},
	boss = {
		radius = 66,
		speed = 60,
		hp = 1050,
		contact = 30,
		score = 260,
		shape = "boss",
		color = "danger",
		fireInterval = 1.5,
	},
}

-- Wave scripts: what spawns, how fast, and how hard the wave hits.
Config.Waves = {
	{
		label = "CONTACT",
		spawnInterval = 0.55,
		spawns = { { kind = "drone", count = 9 } },
	},
	{
		label = "SWARM",
		spawnInterval = 0.45,
		spawns = { { kind = "drone", count = 10 }, { kind = "dart", count = 7 } },
	},
	{
		label = "CROSSFIRE",
		spawnInterval = 0.40,
		spawns = { { kind = "dart", count = 12 }, { kind = "drone", count = 6 }, { kind = "turret", count = 2 } },
	},
	{
		label = "SIEGE",
		spawnInterval = 0.60,
		spawns = { { kind = "brute", count = 6 }, { kind = "dart", count = 10 }, { kind = "turret", count = 3 } },
	},
	{
		label = "THE CORE",
		spawnInterval = 1.15,
		spawns = { { kind = "boss", count = 1 }, { kind = "drone", count = 8 }, { kind = "dart", count = 6 } },
	},
}

Config.MaxWave = #Config.Waves

-- Upgrade picks offered between waves. `apply` mutates the run's stat table, so the
-- simulation reads one set of numbers no matter how the player has built.
Config.Upgrades = {
	{
		id = "rapid",
		name = "OVERCLOCK",
		desc = "Fire rate +30%",
		apply = function(stats)
			stats.fireInterval = stats.fireInterval / 1.3
		end,
	},
	{
		id = "damage",
		name = "HEAVY ROUNDS",
		desc = "Bullet damage +35%",
		apply = function(stats)
			stats.damage = stats.damage * 1.35
		end,
	},
	{
		id = "speed",
		name = "THRUSTERS",
		desc = "Move speed +18%",
		apply = function(stats)
			stats.speed = stats.speed * 1.18
		end,
	},
	{
		id = "hull",
		name = "REINFORCED HULL",
		desc = "+30 max hull, repaired 30",
		apply = function(stats)
			stats.maxHp = stats.maxHp + 30
			stats.hp = math.min(stats.maxHp, stats.hp + 30)
		end,
	},
	{
		id = "multishot",
		name = "SPLIT BARREL",
		desc = "+1 bullet per shot, wider spread",
		apply = function(stats)
			stats.shots = stats.shots + 1
			stats.spread = stats.spread + 0.13
		end,
	},
	{
		id = "pierce",
		name = "RAILCORE",
		desc = "Bullets pierce 1 more target",
		apply = function(stats)
			stats.pierce = stats.pierce + 1
		end,
	},
	{
		id = "repair",
		name = "NANO REPAIR",
		desc = "Repair 45 hull",
		apply = function(stats)
			stats.hp = math.min(stats.maxHp, stats.hp + 45)
		end,
	},
	{
		id = "drone",
		name = "ORBITAL TURRET",
		desc = "A turret orbits and fires with you",
		apply = function(stats)
			stats.orbitals = stats.orbitals + 1
		end,
	},
}

-- The stats a run starts with, copied and then mutated by upgrades.
function Config.newStats()
	return {
		maxHp = Config.Ship.maxHp,
		hp = Config.Ship.maxHp,
		speed = Config.Ship.speed,
		fireInterval = Config.Ship.fireInterval,
		damage = Config.Ship.damage,
		shots = 1,
		spread = 0.0,
		pierce = 0,
		orbitals = 0,
	}
end

return Config
