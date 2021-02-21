function widget:GetInfo()
  return {
    name      = "Player Centroid Marker",
    desc      = "v0002 Centroid Marker shows information about groups of units on the screen.",
    author    = "Pxtl",
    date      = "2020-02-20",
    license   = "GNU GPL, v2 or later",
    layer     = -20,
    experimental = true,
    enabled   = true,
  }
end

--TODO:
----BUG: why is window not appearing if created at startup?  It only appears if created *after*.
----Find out about new version of Chili?
----Hide on mouseover
----filter out spectators --done, test
----don't show resource bar on gaia --done, test.

local echo = Spring.Echo
local abs = math.abs
local markerWindows = {}
local screen0
local screenHeight, screenWidth = 0,0
local timer = 0

local spGetCameraPosition    	= Spring.GetCameraPosition
local spGetMouseState 			= Spring.GetMouseState
local spGetTeamList				= Spring.GetTeamList
local spGetTeamResources		= Spring.GetTeamResources
local spGetTeamUnits			= Spring.GetTeamUnits
local spGetLocalTeamID			= Spring.GetLocalTeamID
local spGetSpectatingState		= Spring.GetSpectatingState
local spGetUnitTeam 			= Spring.GetUnitTeam
local spGetUnitDefID			= Spring.GetUnitDefID
local spGetUnitHealth			= Spring.GetUnitHealth
local spGetUnitViewPosition  	= Spring.GetUnitViewPosition
local spGetVisibleUnits      	= Spring.GetVisibleUnits
local spIsUnitInView 			= Spring.IsUnitInView
local spWorldToScreenCoords 	= Spring.WorldToScreenCoords
local spGetUnitVelocity			= Spring.GetUnitVelocity
local sqrt = math.sqrt

local function Distance3D(x1, y1, z1, x2, y2, z2)
	return sqrt((x2-x1) * (x2-x1) + (y2-y1) * (y2-y1) + (z2-z1) * (z2-z1))
end

local function Distance2D(x1, y1, x2, y2)
	return sqrt((x2-x1) * (x2-x1) +
		(y2-y1) * (y2-y1))
end

local function ScalarMultiplyVec3(multiple, x, y, z)
	return x * multiple, y * multiple, z * multiple
end

local function AddVec3(x1, y1, z1, x2, y2, z2)
	return x1 + x2, y1 + y2, z1 + z2
end

local function AddScalarMultipliedVec3(scalarMultiple, x, y, z, scaledx, scaledy, scaledz)
	x = x + (scaledx or 0) * scalarMultiple
	y = y + (scaledy or 0) * scalarMultiple
	z = z + (scaledz or 0) * scalarMultiple
	return x, y, z
end

local function DestroyWindows()
	for k, window in pairs(markerWindows) do
		screen0:RemoveChild(window)
		window:Dispose()
	end
	markerWindows = {}
end

local function ReInitialize()
	if DestroyWindows then DestroyWindows() end
end

options_path = 'Settings/Interface/Player Centroid Marker'
options_order = {'showLocalPlayer', 'updateInterval', 'backgroundOpacity', 'nameOpacity', 'CCROpacity', 'resourceBarOpacity', 'radarDotWeight', 'text_height', 'pidP', 'pidI', 'pidD'}
options = {
	showLocalPlayer = {
		name = "Show local player's own marker",
		type = 'bool',
		value = false,
		desc = "Show the marker for the current player.",
		OnChange = function() ReInitialize() end,
		advanced = false
	},
	updateInterval = {
		name = "Update Interval (seconds)",
		type = "number",
		value = 0.5, min = 0.1, max = 4.0, step = 0.1,
		desc = "Higher update frequency has performance costs because the widget must examine every unit on the screen. " ..
		"0.5 seconds is recommended for modern PCs, go higher on older machines",
		OnChange = function() ReInitialize() end,
		advanced = false
	},
	backgroundOpacity = {
		name = "Background Opacity",
		type = "number",
		value = 0.5, min = 0, max = 1, step = 0.05,
		desc = "Show a black box behind the marker - 0 is hidden, 1 is solid",
		OnChange = function() ReInitialize() end,
		advanced = false
	},
	nameOpacity = {
		name = "Player Name Opacity",
		type = "number",
		value = 1, min = 0, max = 1, step =0.05,
		desc = "Show the player's name - 0 is hidden, 1 is solid",
		OnChange = function() ReInitialize() end,
		advanced = false
	},
	CCROpacity = {
		name = "Clan/Country/Rank Opacity",
		type = "number",
		value = 1, min = 0, max = 1, step =0.05,
		desc = "Show the clan, country, and rank icons - 0 is hidden, 1 is solid",
		OnChange = function() ReInitialize() end,
		advanced = false
	},
	resourceBarOpacity = {
		name = "Stat bar opacity",
		type = "number",
		value = 0.5, min = 0, max = 1, step =0.05,
		desc = "Display resource statistics: metal and energy - 0 is hidden, 1 is solid",
		OnChange = function() ReInitialize() end,
		advanced = false
	},
	radarDotWeight = {
		name = "Radar Dot Weight",
		type = "number",
		value = 5, min = 5, max = 200, step = 5,
		desc = "What should be the estimated cost of unknown radar dot units",
		OnChange = function() ReInitialize() end,
		advanced = true
	},
	text_height = {
		name = 'Font Size (10-18)',
		type = 'number',
		value = 13,
		min=10,max=18,step=1,
		OnChange = function() ReInitialize() end,
		advanced = true
	},
	vertical_offset = {
		name = "Marker vertical offset",
		type = "number",
		value = 64, min = 1, max = 500, step = 1,
		desc = "How high, in pixels, should the marker be above the centre of the player's units.",
		OnChange = function() ReInitialize() end,
		advanced = true
	},
	pidP = {
		name = 'PID controller Proportional term (0-50)',
		type = 'number',
		value = 25,
		min=0,max=100,step=5,
		advanced = true
	},
	pidI = {
		name = 'PID controller Integral term (0-1)',
		type = 'number',
		value = 0.1,
		min=0,max=1,step=0.05,
		advanced = true
	},
	pidD = {
		name = 'PID controller Derivative term (0-40)',
		type = 'number',
		value = 10,
		min=0,max=50
		,step=2,
		advanced = true
	}
}

-- how much less should immobile units weigh than mobiles for determine how much
-- the marker likes them?
local immobileUnitWeightMultiplier = 0.0625
-- how much less should incomplete units weigh vs complete ones, before
-- factoring in their completion level?
local incompleteUnitWeightMultiplier = 0.25
-- how long (in seconds) should a marker window take to fade in/out?
local fadeTime = 0.25
-- how far (in elmos) is too far for the marker window to slide, after which it
-- should fade out and reappear there?
local markerWindowJumpLimit = 500

function widget:Initialize()
	Chili = WG.Chili
	screen0 = Chili.Screen0
	widget:ViewResize(Spring.GetViewGeometry())

	if (not Chili) then
		widgetHandler:RemoveWidget()
		return
	end
end

function widget:PlayerChanged(playerID)
	ReInitialize()
end
function widget:PlayerAdded(playerID)
	ReInitialize()
end
function widget:PlayerRemoved(playerID)
	ReInitialize()
end
function widget:GameStart()
	ReInitialize()
end
function widget:Shutdown()
	DestroyWindows()
end

function widget:ViewResize(vsx, vsy)
	screenWidth = vsx
	screenHeight = vsy
end



-- helper function
local function Contains(t, item)
  for k, v in pairs(t) do
    if v == item then return true end
  end
  return false
end

local width_icon_clan = 18
local width_icon_country = 18
local width_icon_rank = 18

local function MakeNewBar(window, o)
	-- pass in anything to override these defaults:
	o.height		= o.height		or 3
	o.min 			= o.min 		or 0
	o.max 			= o.max 		or 1
	o.autosize 		= o.autosize 	or false

	local newBar = Chili.Progressbar:New(o)
	window:AddChild(newBar)
	table.insert(window.pcm_bars, newBar)
	return newBar
end

local function MakeNewIcon(window, o)
-- pass in anything to override these defaults:
	o.width			= o.width		or options.text_height.value + 3
	o.height		= o.height		or options.text_height.value + 3

	local newIcon = Chili.Image:New(o)
	window:AddChild(newIcon)
	table.insert(window.pcm_images, newIcon)
	return newIcon
end

local function CreateWindow(teamID)
	local text_height = options.text_height.value

	local window = Chili.Window:New{
		color = {1,1,1,0},
		--borderColor = {1,1,1,0},
		--parent = Chili.Screen0, -- don't add to screen, use the add-to-screen functionality provided by fade-in.
		dockable = false,
		name="PlayerCentroid" .. teamID,
		padding = {5,5,5,5},
		clientWidth  = 64,
		clientHeight = 16,
		minWidth = 64,
		minHeight = 16,
		useDList = false,
		resizable = false,
		autosize  = true,
		draggable = false,
		savespace = false
	}
	window.borderColor[4] = 0

	--0 is fully faded, 1 is opaque.
	window.pcm_opacity = 0
	-- 1 is becoming opaque, -1 is fading
	window.pcm_opacity_transition = 0
	window.pcm_labels = {}
	window.pcm_bars = {}
	window.pcm_images = {}

	local _,leaderPlayerID,isDead,isAI = Spring.GetTeamInfo(teamID)
	local isGaia = (teamID == Spring.GetGaiaTeamID())
	local playerList = {}

	if isAI or isGaia then
		playerList = {-1}
	else
		local rawPlayerList = Spring.GetPlayerList(teamID, true)
		-- filter out spectators here.
		for i = 1, #rawPlayerList do
			local playerID = rawPlayerList[i]
			local _, active, spectator = Spring.GetPlayerInfo(playerID)
			if not spectator and active then
				table.insert(playerList, playerID)
			end
		end
	end

	-- a team (which is a single "player" in Spring with multiple co-op humans
	-- controlling it) so can have multiple human players so we're going to
	-- write one row in the marker per-player
	for i = 1, #playerList do
		local currentX = 0
		local currentY = (i-1) * text_height
		local playerID = playerList[i]
		local teamcolor = teamID and {Spring.GetTeamColor(teamID)} or {1,1,1,1}
		local playerName = nil

		if isAI then
			local _, aiName = Spring.GetAIInfo(teamID)
			playerName = aiName
		elseif isGaia then
			playerName = "Gaia"
		elseif leaderPlayerID == -1 or isDead then
			playerName = "<abandoned units>"
		elseif playerID then
			local name,active,spectator,teamID,allyTeamID,pingTime,cpuUsage,country,rank,customKeys = Spring.GetPlayerInfo(playerID)
			playerName = name

			local icClan, icRank, icCountry = nil,nil,nil
			if options.CCROpacity.value > 0 then
				icCountry = (country and country ~= '' and ("LuaUI/Images/flags/" .. country ..".png"))
				icRank = ("LuaUI/Images/LobbyRanks/" .. (customKeys.icon or "0_0") .. ".png")

				if customKeys.clan and customKeys.clan ~= "" then
					icClan = "LuaUI/Configs/Clans/" .. customKeys.clan ..".png"
				elseif customKeys.faction and customKeys.faction ~= "" then
					icClan = "LuaUI/Configs/Factions/" .. customKeys.faction .. ".png"
				end

				if icCountry then
					MakeNewIcon(window,{x=currentX, y = currentY, file=icCountry,})
					currentX = currentX + width_icon_country
				end
				if icRank then
					MakeNewIcon(window,{x=currentX, y = currentY, file=icRank,})
					currentX = currentX + width_icon_rank
				end
				if icClan then
					MakeNewIcon(window,{x=currentX, y = currentY, file=icClan,})
					currentX = currentX + width_icon_clan
				end
		    end
		else
			playerName = "noname"
		end

		table.insert(window.pcm_labels, Chili.Label:New{
			x = currentX,
			y = (i-1) * text_height,
			parent = window,
			caption = playerName,
			fontsize = text_height,
			textColor = teamcolor,
		})
	end

	-- put the shared storage bars *below* the list of player within the shared-comm-team
	local currentY = #playerList * text_height

	if options.resourceBarOpacity.value > 0 and not isGaia then
		local _, eStorage = spGetTeamResources(teamID, "energy")
		local _, mStorage = spGetTeamResources(teamID, "metal")
		local barWidth = 48

		-- create storage bars, start with dummy values we'll get proper values later
		-- could be nil if we don't have access to this info eg enemy team
		if eStorage ~= nil then
			window.pcm_m_bar = MakeNewBar(window, {x=0, y=currentY+4, width=barWidth,color = {.7,.75,.9,1},value = 1,})
		end
		if mStorage ~= nil then
			window.pcm_e_bar = MakeNewBar(window, {x=barWidth + 2, y=currentY+4, width=barWidth,color = {1,1,0,1},value = 1,}) 
		end
	end

	return window
end

-- check if numeric value is not a number by testing if it's equal to itself
local function IsNan(num)
	return num ~= num
end

local function UpdateWindowPosition(window, dt)
	--show marker if it's been hidden and shouldshow is true
	if window.pcm_shouldShow and not window:IsDescendantOf(screen0) then
		screen0:AddChild(window)

		-- initialize all values
		window.pcm_opacity = 0
		window.pcm_opacity_transition = 1
		window.pcm_velX, window.pcm_velY, window.pcm_velZ = 0,0,0
		window.pcm_integralX, window.pcm_integralY, window.pcm_integralZ = 0,0,0

		window.pcm_posX, window.pcm_posY, window.pcm_posZ =
			window.pcm_centroidPosX, window.pcm_centroidPosY, window.pcm_centroidPosZ
	end

	--hide window shouldshow is false
	if not window.pcm_shouldShow and window.pcm_opacity == 1 then
		window.pcm_opacity_transition = -1
	end

	-- we don't want to apply acceleration once window is fading
	if window.pcm_shouldShow then
		-- Centroid interpolation here - 30 frames per second
		window.pcm_centroidPosX, window.pcm_centroidPosY, window.pcm_centroidPosZ =
			AddScalarMultipliedVec3(dt * 30, window.pcm_centroidPosX, window.pcm_centroidPosY, window.pcm_centroidPosZ)

		-- PID controller logic here
		local pidP, pidI, pidD = options.pidP.value, options.pidI.value, options.pidD.value

		local projectedX, projectedY, projectedZ = AddScalarMultipliedVec3(timer,
			window.pcm_centroidPosX, window.pcm_centroidPosY, window.pcm_centroidPosZ,
			window.pcm_centroidVelX, window.pcm_centroidVelY, window.pcm_centroidVelZ
		)

		local deltaX = projectedX - window.pcm_posX
		local deltaY = projectedY - window.pcm_posY
		local deltaZ = projectedZ - window.pcm_posZ

		-- avoid large jumps and just fade-transition.
		if abs(deltaX) + abs(deltaY) + abs(deltaZ) > markerWindowJumpLimit then
			window.pcm_shouldShow = false
		end

		window.pcm_integralX, window.pcm_integralY, window.pcm_integralZ = AddVec3(
			window.pcm_integralX, window.pcm_integralY, window.pcm_integralZ,
			deltaX, deltaY, deltaZ
		)

		-- apply PID acceleration
		window.pcm_velX = window.pcm_velX + dt * (pidP * deltaX + pidI * window.pcm_integralX - pidD * (window.pcm_velX - window.pcm_centroidVelX))
		window.pcm_velY = window.pcm_velY + dt * (pidP * deltaY + pidI * window.pcm_integralY - pidD * (window.pcm_velY - window.pcm_centroidVelY))
		window.pcm_velZ = window.pcm_velZ + dt * (pidP * deltaZ + pidI * window.pcm_integralZ - pidD * (window.pcm_velZ - window.pcm_centroidVelZ))
	end

	-- apply velocity to position
	window.pcm_posX = window.pcm_posX + dt * window.pcm_velX
	window.pcm_posY = window.pcm_posY + dt * window.pcm_velY
	window.pcm_posZ = window.pcm_posZ + dt * window.pcm_velZ

	-- debug mode, no PID:
	-- window.pcm_posX = window.pcm_centroidPosX + window.pcm_centroidVelX * timer -- window.pcm_posY + dt * window.pcm_velX
	-- window.pcm_posY = window.pcm_centroidPosY + window.pcm_centroidVelY * timer -- window.pcm_posY + dt * window.pcm_velY
	-- window.pcm_posZ = window.pcm_centroidPosZ + window.pcm_centroidVelZ * timer -- window.pcm_posZ + dt * window.pcm_velZ

	-- apply positional update
	local sx, sy, sz = spWorldToScreenCoords(window.pcm_posX , window.pcm_posY, window.pcm_posZ)

	-- check if it's far-out-of-bounds, if so remove window immediately - can re-fade-it-in after.
	local winPosX = sx - window.width/2
	local winPosY = screenHeight - sy - options.vertical_offset.value - window.height
	if (winPosX == nil or winPosY == nil
		--NaN probably shouldn't happen, but occurred in a bug and crashed the
		--widget so keeping the check here defensively
		or IsNan(winPosX) or IsNan(winPosY)
		or (winPosX > screenWidth)
		or (winPosY > screenHeight)
		or (winPosX < 0 - window.width)
		or (winPosY < 0 - window.height)
	) then
		window.pcm_shouldshow = false --fade it out.
	end
	window:SetPos(winPosX, winPosY)
end

-- the storage value from Spring can't be used raw
-- have to do some cleaning
local function CleanStorage(storage)
	if storage then
		storage = storage - 10000 -- storage has a "hidden 10k" to account for

		if storage > 50000  -- fix for weirdness where sometimes storage is reported as huge
		or storage == 0 -- guard against dividing by zero later, when the fill bar percentage is calculated
		then
			storage = 1000 -- assume it should be 1000
		end
	end
	return storage
end

local function GetPlayerTeamStats(teamID)
	local eCurrent, eStorage, ePull, eIncome, eExpe, eShar, eSent, eReci = spGetTeamResources(teamID, "energy")
	local mCurrent, mStorage, mPull, mIncome, mExpe, mShar, mSent, mReci = spGetTeamResources(teamID, "metal")

	local stats = {}
	stats.eStorage = CleanStorage(eStorage)
	stats.mStorage = CleanStorage(mStorage)

	-- Default these to 1 if the value is nil for some reason.
	-- These should never be 1 in normal play, so if you see
	--   them showing up as 1 then that means that something got nil,
	--   which should perhaps then be looked into further.
	-- Whereas it's quite reasonable for them to sometimes be zero.

	-- stats.mIncome = mIncome or 1
	-- stats.eIncome = eIncome or 1
	stats.mCurrent = mCurrent or 1
	stats.eCurrent = eCurrent or 1

	return stats
end

local function UpdatePlayerTeamStats(window,stats)
	if window.pcm_m_bar then window.pcm_m_bar:SetValue(stats.mCurrent/stats.mStorage) end
	if window.pcm_e_bar then window.pcm_e_bar:SetValue(stats.eCurrent/stats.eStorage) end
end

local function UpdateFadeTransition(window)
	-- apply current opacity-level to all widgets
	local backgroundOpacity = options.backgroundOpacity.value
	local newBackgroundOpacity = backgroundOpacity * window.pcm_opacity

	local nameOpacity = options.nameOpacity.value * window.pcm_opacity
	local CCROpacity = options.CCROpacity.value * window.pcm_opacity
	local resourceBarOpacity = options.resourceBarOpacity.value * window.pcm_opacity

	window.color[4] = newBackgroundOpacity
	window.borderColor[4] = newBackgroundOpacity

	for i=1, #window.pcm_bars do
		local bar = window.pcm_bars[i]
		bar.backgroundColor[4] = resourceBarOpacity
		bar.color[4] = resourceBarOpacity
		bar:SetColor(bar.color)
	end

	for i=1, #window.pcm_labels do
		local label = window.pcm_labels[i]
		label.font.color[4] = nameOpacity
		label.font.outlineColor[4] = nameOpacity
		label:Invalidate()
	end

	for i=1, #window.pcm_images do
		local image = window.pcm_images[i]
		image.color[4] = CCROpacity
		image:Invalidate()
	end
end

local function GetUnitWeight(unitID, ux, uy, uz)
	local unitDefID = spGetUnitDefID(unitID)
	local health, maxHealth, paralyzeDamage, captureProgress, buildProgress = spGetUnitHealth(unitID)
	local unitWeight = options.radarDotWeight.value
	--use metal-cost for weight, cut weight for immobile targets.

	if unitDefID then
		unitWeight = UnitDefs[unitDefID]["metalCost"]
		if UnitDefs[unitDefID]["speed"] < 0.125 then
			unitWeight = unitWeight * immobileUnitWeightMultiplier
		end
	end

	--incomplete units
	if (buildProgress ~= nil and buildProgress ~= 1.0) then
		unitWeight = unitWeight * buildProgress * incompleteUnitWeightMultiplier
	end

	--lower weight for units near the edge-of-screen
	local bufferX = screenWidth * 0.25
	local bufferY = screenHeight * 0.25
	local sx, sy, sz = spWorldToScreenCoords(ux , uy, uz)

	if sx < bufferX then
		unitWeight = unitWeight * sx / bufferX
	elseif sx > screenWidth - bufferX then
		unitWeight = unitWeight * (screenWidth - sx) / bufferX
	end

	if sy < bufferY then
		unitWeight = unitWeight * sy / bufferY
	elseif sy > screenHeight - bufferY then
		unitWeight = unitWeight * (screenHeight - sy) / bufferY
	end

	if unitWeight < 0 then unitWeight = 0 end

	return unitWeight
end

local function CalculateCentroid(window, teamID)
	local teamUnits = spGetTeamUnits(teamID)
	local sumPosX, sumPosY, sumPosZ = 0,0,0
	local sumVelX, sumVelY, sumVelZ = 0,0,0
	local totalWeight = 0
	local unitWeightsCache = {}

	-- first find the main centroid
	for j=1,#teamUnits do
		local unitID = teamUnits[j]
		if spIsUnitInView(unitID) then
			local ux, uy, uz = spGetUnitViewPosition(unitID)
			local unitWeight = GetUnitWeight(unitID, ux, uy, uz)
			unitWeightsCache[unitID] = unitWeight

			--sum up for averages
			sumPosX, sumPosY, sumPosZ = AddScalarMultipliedVec3(unitWeight, sumPosX, sumPosY, sumPosZ, ux, uy, uz)
			totalWeight = totalWeight + unitWeight
		end
	end

	-- now we have total weight and weighted sum, calculate weighted averages
	local centroidPosX, centroidPosY, centroidPosZ =
		ScalarMultiplyVec3(1/totalWeight, sumPosX, sumPosY, sumPosZ)

	-- now, repeat but for proximity
	-- but this time we have the old weights cached
	sumPosX, sumPosY, sumPosZ = 0,0,0
	sumVelX, sumVelY, sumVelZ = 0,0,0
	totalWeight = 0
	for unitID, unitWeight in pairs(unitWeightsCache) do
		local ux, uy, uz = spGetUnitViewPosition(unitID)
		local vx, vy, vz = spGetUnitVelocity(unitID)

		local distance = Distance3D(ux, uy, uz, centroidPosX, centroidPosY, centroidPosZ)
		unitWeight = unitWeight * 1000000.0 / (distance * distance * distance + 1) -- the further the lower, add 1 to prevent /0

		--sum up for averages
		sumPosX, sumPosY, sumPosZ = AddScalarMultipliedVec3(unitWeight, sumPosX, sumPosY, sumPosZ, ux, uy, uz)
		sumVelX, sumVelY, sumVelZ = AddScalarMultipliedVec3(unitWeight, sumVelX, sumVelY, sumVelZ, vx, vy, vz)
		totalWeight = totalWeight + unitWeight
	end

	-- now we have total weight and weighted sum, calculate weighted averages
	centroidPosX, centroidPosY, centroidPosZ =
		ScalarMultiplyVec3(1/totalWeight, sumPosX, sumPosY, sumPosZ)
	local centroidVelX, centroidVelY, centroidVelZ =
		ScalarMultiplyVec3(1/totalWeight * 30.0, sumVelX, sumVelY, sumVelZ) -- 30 frames per second

	if totalWeight > 0 then
		if not window then
			window = CreateWindow(teamID)
			markerWindows[teamID] = window
		end

		window.pcm_centroidPosX, window.pcm_centroidPosY, window.pcm_centroidPosZ =
			centroidPosX, centroidPosY, centroidPosZ

		window.pcm_centroidVelX, window.pcm_centroidVelY, window.pcm_centroidVelZ =
			centroidVelX,centroidVelY,centroidVelZ
	end

	if window then
		window.pcm_shouldShow = totalWeight > 0
	end
end

-- update window-position as often as possible, but the unit-list doesn't need to be updated that frequently.

function widget:Update(dt)
	timer = timer + dt
	local doCalculations = false
	if timer > options.updateInterval.value then
		doCalculations = true
		timer = 0
	end

	local localTeamID = spGetLocalTeamID()
	local isLocalPlayerSpectating = spGetSpectatingState()
	local teams = spGetTeamList()

	for i=1,#teams do
		local teamID = teams[i]
		if isLocalPlayerSpectating or teamID ~= localTeamID or options.showLocalPlayer.value then
			local window = markerWindows[teamID]
			-- unit stuff begins here
			if doCalculations then
				CalculateCentroid(window, teamID)

				-- update m/e bars
				if window then
					local stats = GetPlayerTeamStats(teamID)
					UpdatePlayerTeamStats(window, stats)
				end
			end

			if window then
				UpdateWindowPosition(window, dt)
			end

			if window and window.pcm_opacity_transition ~= 0 then
				-- Fade the window according to its current fade-level
				UpdateFadeTransition(window)

				-- update fade-level
				window.pcm_opacity = window.pcm_opacity + dt / fadeTime * window.pcm_opacity_transition
				if window.pcm_opacity >= 1 then
					window.pcm_opacity = 1
					window.pcm_opacity_transition = 0
				elseif window.pcm_opacity <= 0 then
					window.pcm_opacity = 0
					screen0:RemoveChild(window)
					window.pcm_opacity_transition = 0
				end
			end
		end
	end
end
