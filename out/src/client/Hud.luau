-- Everything the player reads: the status panel, the hull bar, the wave banner, the
-- upgrade picks and the end screens. The HUD owns no game state; it renders the
-- snapshot it is given, and it is the only place that decides how the game looks.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local P = Config.Palette
local ARENA = Config.Arena

local Hud = {}
Hud.__index = Hud

local FONT = Enum.Font.GothamBold
local FONT_BODY = Enum.Font.GothamMedium
local MONO = Enum.Font.Code

local function label(props)
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = FONT
	text.TextColor3 = P.text
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.TextScaled = true
	for key, value in pairs(props) do
		text[key] = value
	end
	return text
end

local function panel(parent, name, position, size, anchor)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = anchor or Vector2.new(0, 0)
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = P.panel
	frame.BackgroundTransparency = 0.18
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = P.panelEdge
	stroke.Parent = frame

	return frame
end

local function constrainText(text, max)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = max
	constraint.MinTextSize = 8
	constraint.Parent = text
end

function Hud.new(gui, onChooseUpgrade)
	local self = setmetatable({}, Hud)
	self.gui = gui
	self.onChooseUpgrade = onChooseUpgrade
	self.bannerTimer = 0
	self.titleTimer = 3.4
	self.shownPhase = nil
	self.cards = {}

	self:buildStatus()
	self:buildHull()
	self:buildHint()
	self:buildBanner()
	self:buildUpgradeOverlay()
	self:buildEndOverlay()
	return self
end

function Hud:buildStatus()
	local frame = panel(self.gui, "Status", UDim2.new(1, -26, 0, 22), UDim2.new(0.215, 0, 0.185, 0), Vector2.new(1, 0))

	local title = label({
		Name = "Title",
		Position = UDim2.fromScale(0.07, 0.06),
		Size = UDim2.fromScale(0.86, 0.16),
		Text = "CORE BREACH",
		TextColor3 = P.cyan,
		Parent = frame,
	})
	constrainText(title, 26)

	local waveCaption = label({
		Name = "WaveCaption",
		Position = UDim2.fromScale(0.07, 0.25),
		Size = UDim2.fromScale(0.4, 0.16),
		Text = "WAVE",
		TextColor3 = P.textDim,
		Parent = frame,
	})
	constrainText(waveCaption, 18)

	local waveValue = label({
		Name = "WaveValue",
		Position = UDim2.fromScale(0.07, 0.38),
		Size = UDim2.fromScale(0.4, 0.26),
		Text = "1 / 5",
		TextColor3 = P.text,
		Font = MONO,
		Parent = frame,
	})
	constrainText(waveValue, 40)

	local scoreCaption = label({
		Name = "ScoreCaption",
		Position = UDim2.fromScale(0.53, 0.25),
		Size = UDim2.fromScale(0.4, 0.16),
		Text = "SCORE",
		TextColor3 = P.textDim,
		Parent = frame,
	})
	constrainText(scoreCaption, 18)

	local scoreValue = label({
		Name = "ScoreValue",
		Position = UDim2.fromScale(0.53, 0.38),
		Size = UDim2.fromScale(0.4, 0.26),
		Text = "0",
		TextColor3 = P.amber,
		Font = MONO,
		Parent = frame,
	})
	constrainText(scoreValue, 40)

	-- Wave pips: five markers that fill as waves are cleared.
	local pips = Instance.new("Frame")
	pips.Name = "Pips"
	pips.Position = UDim2.fromScale(0.07, 0.7)
	pips.Size = UDim2.fromScale(0.86, 0.07)
	pips.BackgroundTransparency = 1
	pips.Parent = frame
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.Padding = UDim.new(0.012, 0)
	pipLayout.Parent = pips

	self.pips = {}
	for index = 1, Config.MaxWave do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. index
		pip.Size = UDim2.fromScale(1 / Config.MaxWave - 0.02, 1)
		pip.BackgroundColor3 = P.panelEdge
		pip.BorderSizePixel = 0
		pip.Parent = pips
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = pip
		self.pips[index] = pip
	end

	local hostiles = label({
		Name = "Hostiles",
		Position = UDim2.fromScale(0.07, 0.8),
		Size = UDim2.fromScale(0.86, 0.14),
		Text = "HOSTILES  0",
		TextColor3 = P.textDim,
		Font = MONO,
		Parent = frame,
	})
	constrainText(hostiles, 20)

	self.waveValue = waveValue
	self.scoreValue = scoreValue
	self.hostiles = hostiles
end

function Hud:buildHull()
	local frame = panel(self.gui, "Hull", UDim2.new(0, 26, 1, -26), UDim2.new(0.34, 0, 0.105, 0), Vector2.new(0, 1))

	local caption = label({
		Name = "HullCaption",
		Position = UDim2.fromScale(0.05, 0.08),
		Size = UDim2.fromScale(0.3, 0.34),
		Text = "HULL",
		TextColor3 = P.textDim,
		Parent = frame,
	})
	constrainText(caption, 18)

	local value = label({
		Name = "HullValue",
		Position = UDim2.fromScale(0.68, 0.08),
		Size = UDim2.fromScale(0.27, 0.34),
		Text = "100",
		TextColor3 = P.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = MONO,
		Parent = frame,
	})
	constrainText(value, 22)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromScale(0.05, 0.52)
	track.Size = UDim2.fromScale(0.9, 0.3)
	track.BackgroundColor3 = Color3.fromRGB(24, 34, 52)
	track.BorderSizePixel = 0
	track.Parent = frame
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 6)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = P.cyan
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, P.green),
		ColorSequenceKeypoint.new(1, P.cyan),
	})
	gradient.Parent = fill

	self.hullFill = fill
	self.hullValue = value
end

function Hud:buildHint()
	local hint = label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.new(0.56, 0, 0.032, 0),
		Text = "WASD / ARROWS  MOVE          MOUSE  AIM          HOLD CLICK / SPACE  FIRE",
		TextColor3 = P.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = FONT_BODY,
		Parent = self.gui,
	})
	constrainText(hint, 20)
	self.hint = hint
end

function Hud:buildBanner()
	local banner = label({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.7, 0.1),
		Text = "",
		TextColor3 = P.cyan,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		Parent = self.gui,
	})
	constrainText(banner, 64)
	self.banner = banner

	local title = label({
		Name = "TitleCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.85, 0.16),
		Text = "CORE BREACH",
		TextColor3 = P.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = self.gui,
	})
	constrainText(title, 104)
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 3
	titleStroke.Color = P.cyan
	titleStroke.Transparency = 0.35
	titleStroke.Parent = title

	local subtitle = label({
		Name = "TitleSub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromScale(0.7, 0.05),
		Text = "SURVIVE FIVE WAVES  ·  BREACH THE CORE",
		TextColor3 = P.cyan,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = MONO,
		Parent = self.gui,
	})
	constrainText(subtitle, 30)

	self.title = title
	self.titleStroke = titleStroke
	self.subtitle = subtitle
end

function Hud:buildUpgradeOverlay()
	local overlay = Instance.new("Frame")
	overlay.Name = "UpgradeOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(4, 7, 14)
	overlay.BackgroundTransparency = 0.28
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 40
	overlay.Parent = self.gui

	local heading = label({
		Name = "Heading",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.fromScale(0.6, 0.07),
		Text = "CHOOSE A MODULE",
		TextColor3 = P.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 41,
		Parent = overlay,
	})
	constrainText(heading, 56)

	local sub = label({
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.345),
		Size = UDim2.fromScale(0.6, 0.035),
		Text = "CLICK A CARD OR PRESS 1 2 3",
		TextColor3 = P.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = MONO,
		ZIndex = 41,
		Parent = overlay,
	})
	constrainText(sub, 22)

	local row = Instance.new("Frame")
	row.Name = "Cards"
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.58)
	row.Size = UDim2.fromScale(0.78, 0.34)
	row.BackgroundTransparency = 1
	row.ZIndex = 41
	row.Parent = overlay

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0.02, 0)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = row

	for index = 1, 3 do
		local card = Instance.new("TextButton")
		card.Name = "Card" .. index
		card.Size = UDim2.fromScale(0.3, 1)
		card.BackgroundColor3 = P.panel
		card.BackgroundTransparency = 0.05
		card.BorderSizePixel = 0
		card.AutoButtonColor = true
		card.Text = ""
		card.ZIndex = 42
		card.Parent = row

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = card
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = P.panelEdge
		stroke.Parent = card

		local keyLabel = label({
			Name = "Key",
			Position = UDim2.fromScale(0.09, 0.07),
			Size = UDim2.fromScale(0.82, 0.1),
			Text = "[" .. index .. "]",
			TextColor3 = P.cyanDim,
			Font = MONO,
			ZIndex = 43,
			Parent = card,
		})
		constrainText(keyLabel, 22)

		local name = label({
			Name = "Name",
			Position = UDim2.fromScale(0.09, 0.22),
			Size = UDim2.fromScale(0.82, 0.2),
			Text = "",
			TextColor3 = P.text,
			ZIndex = 43,
			Parent = card,
		})
		constrainText(name, 34)

		local desc = label({
			Name = "Desc",
			Position = UDim2.fromScale(0.09, 0.46),
			Size = UDim2.fromScale(0.82, 0.36),
			Text = "",
			TextColor3 = P.textDim,
			TextYAlignment = Enum.TextYAlignment.Top,
			Font = FONT_BODY,
			ZIndex = 43,
			Parent = card,
		})
		constrainText(desc, 26)

		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.Position = UDim2.fromScale(0.09, 0.16)
		accent.Size = UDim2.fromScale(0.16, 0.012)
		accent.BackgroundColor3 = P.cyan
		accent.BorderSizePixel = 0
		accent.ZIndex = 43
		accent.Parent = card

		card.Activated = function()
			self:choose(index)
		end
		card.MouseEnter = function()
			TweenService:Create(stroke, TweenInfo.new(0.15), { Color = P.cyan }):Play()
		end
		card.MouseLeave = function()
			TweenService:Create(stroke, TweenInfo.new(0.15), { Color = P.panelEdge }):Play()
		end

		self.cards[index] = { button = card, name = name, desc = desc, stroke = stroke }
	end

	self.upgradeOverlay = overlay
end

function Hud:buildEndOverlay()
	local overlay = Instance.new("Frame")
	overlay.Name = "EndOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(3, 6, 12)
	overlay.BackgroundTransparency = 0.15
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 50
	overlay.Parent = self.gui

	local title = label({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(0.8, 0.13),
		Text = "",
		TextColor3 = P.green,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 51,
		Parent = overlay,
	})
	constrainText(title, 92)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = title
	stroke.Transparency = 0.4

	local sub = label({
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.8, 0.045),
		Text = "",
		TextColor3 = P.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = MONO,
		ZIndex = 51,
		Parent = overlay,
	})
	constrainText(sub, 32)

	local again = label({
		Name = "Again",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.8, 0.04),
		Text = "PRESS R TO REDEPLOY",
		TextColor3 = P.cyan,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = MONO,
		ZIndex = 51,
		Parent = overlay,
	})
	constrainText(again, 28)

	self.endOverlay = overlay
	self.endTitle = title
	self.endStroke = stroke
	self.endSub = sub
end

function Hud:choose(index)
	local card = self.cards[index]
	if not card or not self.currentOffers or not self.currentOffers[index] then
		return
	end
	if self.onChooseUpgrade then
		self.onChooseUpgrade(self.currentOffers[index])
	end
end

function Hud:showWaveBanner(text)
	self.banner.Text = text
	self.bannerTimer = 2.1
end

function Hud:update(snapshot)
	self.snapshot = snapshot

	self.waveValue.Text = snapshot.wave .. " / " .. snapshot.maxWave
	self.scoreValue.Text = string.format("%d", snapshot.score)
	self.hostiles.Text = string.format("HOSTILES  %d", snapshot.remaining)

	local ratio = math.clamp(snapshot.hp / math.max(1, snapshot.maxHp), 0, 1)
	self.hullFill.Size = UDim2.fromScale(ratio, 1)
	self.hullValue.Text = string.format("%d", math.floor(snapshot.hp + 0.5))
	self.hullFill.BackgroundColor3 = ratio > 0.5 and P.cyan or (ratio > 0.25 and P.amber or P.danger)

	for index, pip in ipairs(self.pips) do
		if index < snapshot.wave then
			pip.BackgroundColor3 = P.cyan
		elseif index == snapshot.wave then
			pip.BackgroundColor3 = snapshot.phase == "won" and P.cyan or P.amber
		else
			pip.BackgroundColor3 = P.panelEdge
		end
	end

	-- Upgrade overlay.
	if snapshot.phase == "upgrade" then
		self.currentOffers = snapshot.offers
		self.upgradeOverlay.Visible = true
		for index, card in ipairs(self.cards) do
			local id = snapshot.offers[index]
			local upgrade
			if id then
				for _, candidate in ipairs(Config.Upgrades) do
					if candidate.id == id then
						upgrade = candidate
						break
					end
				end
			end
			if upgrade then
				card.button.Visible = true
				card.name.Text = upgrade.name
				card.desc.Text = upgrade.desc
			else
				card.button.Visible = false
			end
		end
	else
		if self.upgradeOverlay.Visible then
			self.upgradeOverlay.Visible = false
			self.currentOffers = nil
		end
	end

	-- End screens.
	if snapshot.phase == "won" or snapshot.phase == "lost" then
		if self.shownPhase ~= snapshot.phase then
			self.shownPhase = snapshot.phase
			self.endOverlay.Visible = true
			if snapshot.phase == "won" then
				self.endTitle.Text = "CORE BREACHED"
				self.endTitle.TextColor3 = P.green
				self.endStroke.Color = P.green
			else
				self.endTitle.Text = "HULL LOST"
				self.endTitle.TextColor3 = P.danger
				self.endStroke.Color = P.danger
			end
			self.endSub.Text = string.format(
				"SCORE %d   ·   WAVES %d/%d   ·   KILLS %d",
				snapshot.score,
				snapshot.phase == "won" and snapshot.maxWave or math.max(0, snapshot.wave - 1),
				snapshot.maxWave,
				snapshot.kills
			)
		end
	else
		self.shownPhase = nil
		self.endOverlay.Visible = false
	end
end

function Hud:step(dt)
	-- Wave banner: fade in fast, hold, fade out.
	if self.bannerTimer > 0 then
		self.bannerTimer = math.max(0, self.bannerTimer - dt)
		local life = self.bannerTimer
		local alpha
		if life > 1.7 then
			alpha = (2.1 - life) / 0.4
		elseif life > 0.5 then
			alpha = 1
		else
			alpha = life / 0.5
		end
		self.banner.TextTransparency = 1 - math.clamp(alpha, 0, 1)
	else
		self.banner.TextTransparency = 1
	end

	-- Title card: held at the start of a round, then gone.
	if self.titleTimer > 0 then
		self.titleTimer = math.max(0, self.titleTimer - dt)
		local alpha = math.clamp((self.titleTimer - 0.6) / 0.9, 0, 1)
		self.title.TextTransparency = 1 - alpha
		self.subtitle.TextTransparency = 1 - alpha
		self.titleStroke.Transparency = 1 - alpha * 0.65
	else
		self.title.TextTransparency = 1
		self.subtitle.TextTransparency = 1
		self.titleStroke.Transparency = 1
	end
end

function Hud:resetRound()
	self.titleTimer = 3.4
	self.bannerTimer = 0
	self.shownPhase = nil
	self.endOverlay.Visible = false
	self.upgradeOverlay.Visible = false
	self.currentOffers = nil
end

return Hud
