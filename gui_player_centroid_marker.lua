function widget:GetInfo()
  return {
    name      = "Player Centroid Marker",
    desc      = "v0001 Centroid Marker shows information about groups of units on the screen.",
    author    = "Pxtl",
    date      = "2014-01-31",
    license   = "GNU GPL, v2 or later",
    layer     = -20,
    experimental = true,
    enabled   = true,
  }
end

--TODO:
----alpha foreground -- DONE, test
----avoid large jumps in position -- DONE, configurize
----ignore buildings
----ignore units near edge of view
----is destroying windows failing maybe?  Windows seem to get abandoned. -- DONE, test NOOOO still working on this... maybe fixed now?
----confirm that unit values are being properly considered -- DONE, yes, they are.
----filter out spectators --done, test
----don't show resource bar on gaia --done, test.

local echo = Spring.Echo
local abs = math.abs
local markerWindows = {}
local screen0
local screenHeight, screenWidth = 0,0
local histogramRows = 4
local histogramColumns = 8

local spGetCameraPosition    	= Spring.GetCameraPosition
local spGetTeamList				= Spring.GetTeamList
local spGetTeamResources		= Spring.GetTeamResources
local spGetTeamUnits			= Spring.GetTeamUnits
local spGetUnitTeam 			= Spring.GetUnitTeam
local spGetUnitDefID			= Spring.GetUnitDefID
local spGetUnitViewPosition  	= Spring.GetUnitViewPosition
local spGetVisibleUnits      	= Spring.GetVisibleUnits
local spIsUnitInView 			= Spring.IsUnitInView
local spWorldToScreenCoords 	= Spring.WorldToScreenCoords
local spGetUnitVelocity			= Spring.GetUnitVelocity

local function ReInitialize()
	if DestroyWindows then DestroyWindows() end
end

options_path = 'Settings/Interface/Player Centroid Marker'
options_order = {'radarDotWeight', 'showLocalPlayer', 'backgroundOpacity', 'nameOpacity', 'eloOpacity', 'CCROpacity', 'statsOpacity', 'text_height', 'pidP', 'pidI', 'pidD'}
options = {
	radarDotWeight = {
		name = "Radar Dot Weight",
		type = "number",
		value = 20, min = 1, max = 500, step = 1,
		OnChange = function() ReInitialize() end,
		advanced = true
	},
	showLocalPlayer = {
		name = "Show local player's own marker",
		type = 'bool',
		value = false,
		desc = "Show the marker for the current player.",
		OnChange = function() ReInitialize() end,
	},
	backgroundOpacity = {
		name = "Background Opacity",
		type = "number",
		value = 0.0, min = 0, max = 1, step = 0.05,
		OnChange = function() ReInitialize() end,
	},
	nameOpacity = {
		name = "Player Name Opacity",
		type = "number",
		value = 1, min = 0, max = 1, step =0.05,
		desc = "Show the player's name - 0 is hidden, 1 is solid",
		OnChange = function() ReInitialize() end,
	},
	eloOpacity = {
		name = "Player ELO Opacity",
		type = "number",
		value = 0.0, min = 0, max = 1, step =0.05,
		desc = "Show the player's ELO - 0 is hidden, 1 is solid",
		OnChange = function() ReInitialize() end,
	},
	CCROpacity = {
		name = "Clan/Country/Rank Opacity",
		type = "number",
		value = 0.75, min = 0, max = 1, step =0.05,
		desc = "Show the clan, country, and rank icons - 0 is hidden, 1 is solid",
		OnChange = function() ReInitialize() end,
	},
	statsOpacity = {
		name = "Stat bar opacity",
		type = "number",
		value = 0.0, min = 0, max = 1, step =0.05,
		desc = "Display resource statistics: metal and energy - 0 is hidden, 1 is solid",
		OnChange = function() ReInitialize() end,
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
		name = 'PID controller Proportional term (0-128)',
		type = 'number',
		value = 32,
		min=0,max=128,step=1,
		advanced = true
	},
	pidI = {
		name = 'PID controller Integral term (0-0.01)',
		type = 'number',
		value = 0.005,
		min=0,max=0.01,step=0.0001,
		advanced = true
	},
	pidD = {
		name = 'PID controller Derivative term (0-128)',
		type = 'number',
		value = 16,
		min=0,max=128,step=1,
		advanced = true
	}
}

function widget:Initialize()
	Chili = WG.Chili
	screen0 = Chili.Screen0
	widget:ViewResize(Spring.GetViewGeometry())
	
	if (not Chili) then
		widgetHandler:RemoveWidget()
		return
	end
end

histogram = {}
local function MakeHistogramTable()
	for i = 1, histogramRows do
		-- create the row if it does not exist
		if histogramRows[i] == nil then
			histogram[i] = {}
		end

		for j = 1, histogramColumns do
			histogram[i][j] = 0;
		end
	end
end	

local function DestroyWindows()
	for k, window in pairs(markerWindows) do
		screen0:RemoveChild(window)
		window:Dispose()
	end
	markerWindows = {}
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
local width_icon_country = 20
local width_icon_rank = 16
local width_elo = 32

local function MakeNewLabel(parent, o) -- "o" is for options
	-- pass in any optional params like align
	-- pass in anything to override these defaults:

	local newLabel = Label:New(o)
	parent:AddChild(newLabel)
end

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

local function FormatElo(elo)
	local mult = 50
	local elo_out = mult * math.floor((elo/mult) + .5)
	local eloColor = {}

	local top = 1800
	local mid = 1600
	local bot = 1400
	local tc = {1,1,1,1}
	local mc = {1,1,0,1}
	local bc = {1,.2,.2,1}
	
	if elo_out >= top then eloColor = tc
	elseif elo_out >= mid then
		local r = (elo_out-mid)/(top-mid)
		for i = 1,4 do
			eloColor[i] = (r * tc[i]) + ((1-r) * mc[i])
		end
	elseif elo_out >= bot then
		local r = (elo_out-bot)/(mid-bot)
		for i = 1,4 do
			eloColor[i] = (r * mc[i]) + ((1-r) * bc[i])
		end
	else eloColor = bc
	end

	return elo_out, eloColor
end

local function CreateWindow(teamID)	
	local screenWidth,screenHeight = Spring.GetWindowGeometry()
	local text_height = options.text_height.value
	
	local window = Chili.Window:New{
		color = {1,1,1,0},
		borderColor = {1,1,1,0},
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
		savespace = true
	}
	window.pcm_fade = 1 --1 is fully faded.
	window.pcm_fading_direction = 0
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
	
	local i = 1;
	for i = 1, #playerList do
		local currentX = 0
		local playerID = playerList[i]
		local teamcolor = teamID and {Spring.GetTeamColor(teamID)} or {1,1,1,1}
		local playername = nil
			
		if isAI then
			local _, aiName, _, shortName = Spring.GetAIInfo(teamID)
			playerName = aiName ..' ('.. shortName .. ')'
		elseif isGaia then
			playerName = "Gaia"
		elseif leaderPlayerID == -1 or isDead then
			playerName = "<abandoned units>"
		elseif playerID then
			local name,active,spectator,teamID,allyTeamID,pingTime,cpuUsage,country,rank,customKeys = Spring.GetPlayerInfo(playerID)
			playerName = name
			-- DEBUG MODE playerName = name .. ", active:" .. tostring(active) .. ", spectator:".. tostring(spectator) .. ", leaderPlayerID:".. tostring(leaderPlayerID) .. ", isDead:".. tostring(isDead)
			local clan, faction, level, elo
			if customKeys then
				clan = customKeys.clan
				faction = customKeys.faction
				level = customKeys.level
				elo = customKeys.elo
			end
			local icon = nil
			local icRank = nil 
			local eloColor = nil
			local icCountry = nil
			if options.CCROpacity.value > 0 then
				if country and country ~= '' and country ~= '??' then icCountry = "LuaUI/Images/flags/" .. (country) .. ".png" end
				if level and level ~= "" then icRank = "LuaUI/Images/Ranks/" .. math.min((1+math.floor((level or 0)/10)),9) .. ".png" end
				if clan and clan ~= "" then 
					icon = "LuaUI/Configs/Clans/" .. clan ..".png"
				elseif faction and faction ~= "" then
					icon = "LuaUI/Configs/Factions/" .. faction ..".png"
				end
				
				if icCountry then 
					MakeNewIcon(window,{x=currentX, y = (i-1) * text_height, file=icCountry,}) 
					currentX = currentX + width_icon_country
				end 
				if icRank then 
					MakeNewIcon(window,{x=currentX, y = (i-1) * text_height, file=icRank,}) 
					currentX = currentX + width_icon_rank
				end
				if icon then 
					MakeNewIcon(window,{x=currentX, y = (i-1) * text_height, file=icon,}) 
					currentX = currentX + width_icon_clan
				end 
		    end
			if elo and elo ~= "" then
				elo, eloColor = FormatElo(elo)
			end
			if elo and options.eloOpacity.value > 0 then 
				window.pcm_eloLabel = Chili.Label:New{
					x=currentX,
					y = (i-1) * text_height,
					parent = window,
					caption = elo,
					fontsize = text_height,
					textColor = eloColor,
				}
				currentX = currentX + width_elo
			end
		else
			playername = "noname"
		end
		
		window.pcm_nameLabel = Chili.Label:New{
			x = currentX,
			y = (i-1) * text_height,
			parent = window,
			caption = playerName,
			fontsize = text_height,
			textColor = teamcolor,
		}
	end
	
	if options.statsOpacity.value > 0 and not isGaia then
		local eCurrent, eStorage = spGetTeamResources(teamID, "energy")
		local mCurrent, mStorage = spGetTeamResources(teamID, "metal")
		if eStorage then window.pcm_m_bar = MakeNewBar(window, {x=0, y= i * text_height + 2, width=64,color = {.7,.75,.9,1},value = 1,}) end
		if mStorage then window.pcm_e_bar = MakeNewBar(window, {x=66, y= i * text_height + 2, width=64,color = {1,1,0,1},value = 1,}) end
	end
	
	return window
end

local function UpdateWindowPosition(window, dt)
	if window and not Contains(markerWindows, window) then
		echo("ERROR: UpdateWindowPosition assertion failed.")
	end
	
	--show marker if it's been hidden and shouldshow is true
	if window.pcm_shouldShow and not window:IsDescendantOf(screen0) then
		screen0:AddChild(window)
		window.pcm_fade = 1
		window.pcm_fading_direction = -1
		
		window.pcm_velX = 0
		window.pcm_velY = 0
		window.pcm_velZ = 0
		window.pcm_integralX = 0
		window.pcm_integralY = 0
		window.pcm_integralZ = 0
		window.pcm_posX = window.pcm_centroidPosX
		window.pcm_posY = window.pcm_centroidPosY
		window.pcm_posZ = window.pcm_centroidPosZ
	end
	
	--hide window shouldshow is false
	if not window.pcm_shouldShow and window and window.pcm_fade == 0 then
		window.pcm_fading_direction = 1
	end
	
	if window.pcm_shouldShow then
		-- Centroid interpolation here
		window.pcm_centroidPosX = window.pcm_centroidPosX + window.pcm_centroidVelX * dt * 30	
		window.pcm_centroidPosY = window.pcm_centroidPosY + window.pcm_centroidVelY * dt * 30		
		window.pcm_centroidPosZ = window.pcm_centroidPosZ + window.pcm_centroidVelZ * dt * 30
		
		-- PID controller logic here
		local pidP = options.pidP.value
		local pidI = options.pidI.value
		local pidD = options.pidD.value
		
		local deltaX = window.pcm_centroidPosX - window.pcm_posX
		local deltaY = window.pcm_centroidPosY - window.pcm_posY
		local deltaZ = window.pcm_centroidPosZ - window.pcm_posZ
		
		-- avoid large jumps and just fade-transition.
		if abs(deltaX) + abs(deltaY) + abs(deltaZ) > 500 then --TODO: parametrize me
			window.pcm_shouldShow = false
		end
	
		window.pcm_integralX = window.pcm_integralX + deltaX
		window.pcm_integralY = window.pcm_integralY + deltaY
		window.pcm_integralZ = window.pcm_integralZ + deltaZ
		
		-- apply PID acceleration
		window.pcm_velX = window.pcm_velX + dt * (pidP * deltaX + pidI * window.pcm_integralX - pidD * (window.pcm_velX - window.pcm_centroidVelX)) 
		window.pcm_velY = window.pcm_velY + dt * (pidP * deltaY + pidI * window.pcm_integralY - pidD * (window.pcm_velY - window.pcm_centroidVelY)) 
		window.pcm_velZ = window.pcm_velZ + dt * (pidP * deltaZ + pidI * window.pcm_integralZ - pidD * (window.pcm_velZ - window.pcm_centroidVelZ)) 
		
		-- apply velocity to position
		window.pcm_posX = window.pcm_posX + dt * window.pcm_velX
		window.pcm_posY = window.pcm_posY + dt * window.pcm_velY
		window.pcm_posZ = window.pcm_posZ + dt * window.pcm_velZ
	end
	
	-- apply positional update
	local sx, sy, sz = spWorldToScreenCoords(window.pcm_posX , window.pcm_posY, window.pcm_posZ)
	--local sx, sy, sz = spWorldToScreenCoords(window.pcm_centroidPosX , window.pcm_centroidPosY, window.pcm_centroidPosZ)
	window:SetPos(sx - window.width/2,screenHeight-sy - options.vertical_offset.value - window.height)	
	
	-- check if out-of-bounds, if so remove window immediately - can re-fade-it-in after.
	if (window.x > screenWidth) 
	or (window.y > screenHeight)
	or (0 > window.x + window.width) 
	or (0 > window.y + window.height) 
	then
		screen0:RemoveChild(window)
	end
end

local isImmobileUnitWeightMultiplier = 0.125
local fadeTime = 0.25

local function GetPlayerTeamStats(teamID)
	local eCurrent, eStorage, ePull, eIncome, eExpe, eShar, eSent, eReci = spGetTeamResources(teamID, "energy")
	local mCurrent, mStorage, mPull, mIncome, mExpe, mShar, mSent, mReci = spGetTeamResources(teamID, "metal")
	if eStorage then
		eStorage = eStorage - 10000					-- eStorage has a "hidden 10k" to account for
		if eStorage > 50000 then eStorage = 1000 end	-- fix for weirdness where sometimes storage is reported as huge, assume it should be 1000
	end
	-- guard against dividing by zero later, when the fill bar percentage is calculated
	-- these probably aren't ever going to be zero, but better safe than sorry
	if mStore and mStore == 0 then mStore = 1000 end
	if eStore and eStore == 0 then eStore = 1000 end

	-- Default these to 1 if the value is nil for some reason.
	-- These should never be 1 in normal play, so if you see
	--   them showing up as 1 then that means that something got nil,
	--   which should perhaps then be looked into further.
	-- Whereas it's quite reasonable for them to sometimes be zero.
	local stats = {}
	stats.mIncome = mIncome or 1
	stats.eIncome = eIncome or 1
	stats.mCurrent = mCurrent or 1
	stats.mStorage = mStorage or 1
	stats.eCurrent = eCurrent or 1
	stats.eStorage = eStorage or 1
	
	return stats
end

local function UpdatePlayerTeamStats(window,stats)
	if window.pcm_m_bar then window.pcm_m_bar:SetValue(stats.mCurrent/stats.mStorage) end
	if window.pcm_e_bar then window.pcm_e_bar:SetValue(stats.eCurrent/stats.eStorage) end
end

local function UpdateFade(window)
	-- apply current fade-level to all widgets
	local backgroundOpacity = options.backgroundOpacity.value
	local newBackgroundOpacity = backgroundOpacity - backgroundOpacity * window.pcm_fade
	
	local nameOpacity = options.nameOpacity.value * (1 - window.pcm_fade)	
	local eloOpacity = options.eloOpacity.value * (1 - window.pcm_fade)	
	local CCROpacity = options.CCROpacity.value * (1 - window.pcm_fade)	
	local statsOpacity = options.statsOpacity.value * (1 - window.pcm_fade)
	
	window.color[4] = newBackgroundOpacity
	window.borderColor[4] = newBackgroundOpacity
	
	for j=1, #window.pcm_bars do
		local bar = window.pcm_bars[j]
		bar.backgroundColor[4] = statsOpacity 
		bar.color[4] = statsOpacity
		bar:SetColor(bar.color)
	end
	
	window.pcm_nameLabel.font.color[4] = nameOpacity 
	window.pcm_nameLabel.font.outlineColor[4] = nameOpacity
	window.pcm_nameLabel:Invalidate()
	
	if window.pcm_eloLabel then 
		window.pcm_eloLabel.font.color[4] = eloOpacity 
		window.pcm_eloLabel.font.outlineColor[4] = eloOpacity
		window.pcm_eloLabel:Invalidate()
	end
	
	for j=1, #window.pcm_images do
		local image = window.pcm_images[j]
		image.color[4] = CCROpacity
		image:Invalidate()
	end
end

local function GetUnitWeight(unitDefID, ux, uy, uz)
	local unitWeight = options.radarDotWeight.value
	--use metal-cost for weight, cut weigh for immobile targets.
	if unitDefID then
		unitWeight = UnitDefs[unitDefID]["metalCost"]
		if UnitDefs[unitDefID]["speed"] < 0.125 then
			unitWeight = unitWeight * isImmobileUnitWeightMultiplier 
		end
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
	local sumPosX = 0
	local sumPosY = 0
	local sumPosZ = 0
	local sumVelX = 0
	local sumVelY = 0
	local sumVelZ = 0
	local totalWeight = 0
	for j=1,#teamUnits do
		local unitID = teamUnits[j]
		if spIsUnitInView(unitID) then
			local ux, uy, uz = spGetUnitViewPosition(unitID)
			local vx, vy, vz = spGetUnitVelocity(unitID)
			local unitDefID = spGetUnitDefID(unitID)
			
			local unitWeight = GetUnitWeight(unitDefID, ux, uy, uz)
			
			--sum up for averages
			sumPosX = sumPosX + ux * unitWeight
			sumPosY = sumPosY + uy * unitWeight
			sumPosZ = sumPosZ + uz * unitWeight
			
			sumVelX = sumVelX + (vx or 0) * unitWeight
			sumVelY = sumVelY + (vy or 0) * unitWeight
			sumVelZ = sumVelZ + (vz or 0) * unitWeight
			
			totalWeight = totalWeight + unitWeight
		end
	end
	
	if totalWeight > 0 then
		if not window then
			window = CreateWindow(teamID)
			markerWindows[teamID] = window
		end
		window.pcm_centroidPosX = sumPosX / totalWeight
		window.pcm_centroidPosY = sumPosY / totalWeight
		window.pcm_centroidPosZ = sumPosZ / totalWeight
		
		window.pcm_centroidVelX = sumVelX / totalWeight
		window.pcm_centroidVelY = sumVelY / totalWeight
		window.pcm_centroidVelZ = sumVelZ / totalWeight
	end
	
	if window then
		window.pcm_shouldShow = totalWeight > 0
	end
end

local UNIT_UPDATE_FREQUENCY = 0.5 -- seconds
-- update window-position as often as possible, but the unit-list doesn't need to be updated that frequently.
local timer = 0
function widget:Update(dt)
	timer = timer + dt
	local doCalculations = false
	if timer > UNIT_UPDATE_FREQUENCY then
		doCalculations = true
		timer = 0
	end
	
	local localTeamID = Spring.GetLocalTeamID()
	local isLocalPlayerSpectating = Spring.GetSpectatingState()
	local teams = spGetTeamList()
	for i=1,#teams do
		local teamID = teams[i]
		if isLocalPlayerSpectating or teamID ~= localTeamID or options.showLocalPlayer.value then
			local window = markerWindows[teamID]
			-- unit stuff begins here
			if doCalculations then
				CalculateCentroid(window, teamID)
			end
			
			if window then 		
				UpdateWindowPosition(window, dt)
			end
			
			if window and window.pcm_fading_direction ~= 0 then
				-- Fade the window according to its current fade-level
				UpdateFade(window)
				
				-- update fade-level
				window.pcm_fade = window.pcm_fade + dt / fadeTime * window.pcm_fading_direction
				if window.pcm_fade >= 1 then
					window.pcm_fade = 1
					screen0:RemoveChild(window)
					window.pcm_fading_direction = 0
				elseif window.pcm_fade <= 0 then
					window.pcm_fade = 0
					window.pcm_fading_direction = 0
				end
			end	
			
			-- update m/e bars
			if window then
				local stats = GetPlayerTeamStats(teamID)
				UpdatePlayerTeamStats(window, stats)
			end
		end
	end
end
