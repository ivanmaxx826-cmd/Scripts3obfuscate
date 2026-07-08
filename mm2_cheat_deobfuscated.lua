--[[ ============================================================================
  MM2 CHEAT — ДЕОБФУСЦИРОВАННЫЙ ИСХОДНИК (Murder Mystery 2)
  ----------------------------------------------------------------------------
  Получено анализом связки project-reverse.org.
  Слой:      MoonVeil Obfuscator v1.4.5 (виртуализированный загрузчик) -> снят
  Способ:    песочница-харнесс перехватила loadstring() второй стадии
             БЕЗ ЕЁ ВЫПОЛНЕНИЯ и сохранила исходник целиком.
  Размер:    45 312 байт, 1188 строк, 45 функций.

  РЕЗУЛЬТАТ IOC-СКАНА (сеть/выгрузка данных):
    * HttpGet / HttpPost / HttpService / request / http_request .. НЕ НАЙДЕНО
    * webhook / discord / SendAsync / PostAsync / base64 ........ НЕ НАЙДЕНО
    * writefile / readfile / getgenv / hookfunction ............. НЕ НАЙДЕНО
    * setclipboard .............. только заглушка-нейтрализация (строка 1)
    * :FireServer ............... только Knife.Stab:FireServer (строка ~394)
  ВЫВОД: это чистый gameplay-чит для MM2, БЕЗ стилера/бимера в данной стадии.
         (Настоящий риск выгрузки, если есть, — в загрузчике mm2.luau / Luraph,
          который запускается ПЕРВЫМ; он здесь НЕ проанализирован.)

  ВНИМАНИЕ: это всё равно чит — использование = БАН-РИСК для аккаунта Roblox.
            Запускать только на мусорном аккаунте в изолированной среде.
            Материал предоставлен для анализа/деобфускации, не для игры.

  ----------------------------------------------------------------------------
  КАРТА СЕКЦИЙ (номера строк — в этом файле, со сдвигом на шапку):
    Движение/защита : enableAntiFling, enableNoclip, createFloatingPad,
                      forceServerSync, setCharacterVisibility
    Логика монет    : isCoinValid, findActiveCoinContainer, findNearestCoin,
                      isRoundActive, allCoinsGone, getActiveMap
    Анти-убийца     : getMurdererHRP, isCoinNearMurderer (avoidMurderCoins)
    Авто-фарм       : doNormalFarm/normalFarmMain (Normal),
                      doSafe2Farm/safeFarmMain (Underground/Safe2)
    Конец раунда    : handleRoundEnd (P1 Lobby / P2 Kill-All / P3 AutoReset)
    Kill-aura       : glueConnection + Knife.Stab:FireServer("Slash") x8s
    Anti-AFK        : enableAntiAfk (VirtualUser)
    Главный цикл    : startFarmLoop
    Интерфейс (GUI) : makeTabBtn, switchTab, makePage, makeToggle,
                      makeSlider, weapon-spawn (doSpawn), makeDraggable
============================================================================ ]]

setclipboard = function() end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local localplayer = Players.LocalPlayer

local tweenSpeed = 15
local safe2UndergroundOffset = -6.5
local safe2PickupOffsetY = -2.5
local PAD_Y_OFFSET = -3.5

local farmMode = nil
local autoFarm = false
local autoResetEnabled = false
local autoSlashEnabled = false
local antiAfkEnabled = false
local avoidMurderCoins = false
local waitInLobbyEnabled = false
local deadUntilNextRound = false
local visitedCoins = {}
local activeTween = nil
local antiAfkConnection = nil
local humanoidDiedConn = nil
local waitingForNewMap = false
local farmLoopRunning = false
local noclipConnections = {}
local isSpectatingMidRound = false
local fakeFloor = nil
local padFollowConnection = nil
local antiFlingConnection = nil

local killEveryoneActive = false
local originalKillData = {}
local glueConnection = nil
local gluedPlayers = {}

local LOBBY_POSITION = CFrame.new(13.6, 504.8, -50.2)

local function enableAntiFling()
	if antiFlingConnection then return end
	local speaker = localplayer
	antiFlingConnection = RunService.PreSimulation:Connect(function()
		if not autoFarm and not autoSlashEnabled then return end
		for _, player in pairs(Players:GetPlayers()) do
			if player ~= speaker and player.Character then
				for _, v in pairs(player.Character:GetDescendants()) do
					if v:IsA("BasePart") then v.CanCollide = false end
				end
			end
		end
	end)
end

local function disableAntiFling()
	if antiFlingConnection then antiFlingConnection:Disconnect(); antiFlingConnection = nil end
	for _, player in pairs(Players:GetPlayers()) do
		if player ~= localplayer and player.Character then
			for _, v in pairs(player.Character:GetDescendants()) do
				if v:IsA("BasePart") then v.CanCollide = true end
			end
		end
	end
end

local function enableNoclip()
	for _, conn in pairs(noclipConnections) do pcall(function() conn:Disconnect() end) end
	noclipConnections = {}
	local char = localplayer.Character
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then part.CanCollide = false end
	end
	local c1 = char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then d.CanCollide = false end
	end)
	table.insert(noclipConnections, c1)
	local c2 = RunService.PreSimulation:Connect(function()
		if char and char.Parent then
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
			end
		end
	end)
	table.insert(noclipConnections, c2)
end

local function disableNoclip()
	for _, conn in pairs(noclipConnections) do pcall(function() conn:Disconnect() end) end
	noclipConnections = {}
	local char = localplayer.Character
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then part.CanCollide = true end
	end
end

local function createFloatingPad()
	if fakeFloor and fakeFloor.Parent then fakeFloor:Destroy() end
	if padFollowConnection then padFollowConnection:Disconnect(); padFollowConnection = nil end
	local pad = Instance.new("Part")
	pad.Anchored = true; pad.CanCollide = true
	pad.Size = Vector3.new(10, 1, 10); pad.Transparency = 1
	pad.CanQuery = false; pad.CastShadow = false
	pad.Name = "FloatingPad"; pad.Parent = Workspace
	fakeFloor = pad
	padFollowConnection = RunService.PreSimulation:Connect(function()
		local char = localplayer.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp and pad and pad.Parent then
			pad.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y + PAD_Y_OFFSET, hrp.Position.Z)
		end
	end)
end

local function removeInvisibleFloor()
	if padFollowConnection then padFollowConnection:Disconnect(); padFollowConnection = nil end
	if fakeFloor and fakeFloor.Parent then fakeFloor:Destroy() end
	fakeFloor = nil
end

local function cancelActiveTween()
	if activeTween then pcall(function() activeTween:Cancel() end); activeTween = nil end
end

local function anchorHRP(hrp, state)
	if hrp then hrp.Anchored = state end
end

local function forceServerSync(char)
	if char and char.PrimaryPart then
		char:PivotTo(CFrame.new(char.PrimaryPart.Position))
		char.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
	end
end

local function setCharacterVisibility(visible)
	local char = localplayer.Character
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then part.LocalTransparencyModifier = visible and 0 or 1 end
	end
end

local function isCoinValid(coin)
	if not coin or not coin.Parent then return false end
	if not coin:IsDescendantOf(Workspace) then return false end
	if not coin:IsA("BasePart") then return false end
	return coin:FindFirstChild("CoinVisual") ~= nil
end

local function findActiveCoinContainer()
	for _, child in ipairs(Workspace:GetChildren()) do
		local cc = child:FindFirstChild("CoinContainer")
		if cc then return cc, child end
	end
	return nil, nil
end

local MURDERER_DANGER_RADIUS = 20
local function getMurdererHRP()
	for _, player in ipairs(Players:GetPlayers()) do
		if player == localplayer then continue end
		local char = player.Character
		if not char then continue end
		local hasKnife = char:FindFirstChild("Knife") ~= nil
		if not hasKnife then
			local bp = player:FindFirstChild("Backpack")
			if bp then hasKnife = bp:FindFirstChild("Knife") ~= nil end
		end
		if hasKnife then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then return hrp end
		end
	end
	return nil
end

local function isCoinNearMurderer(coinPos)
	if not avoidMurderCoins then return false end
	local murderHRP = getMurdererHRP()
	if not murderHRP then return false end
	return (murderHRP.Position - coinPos).Magnitude < MURDERER_DANGER_RADIUS
end

local function findNearestCoin(hrp)
	local nearest, bestDist = nil, math.huge
	local coinContainer = findActiveCoinContainer()
	if coinContainer then
		for _, coin in ipairs(coinContainer:GetChildren()) do
			if coin:IsA("BasePart") and coin.Name == "Coin_Server"
				and isCoinValid(coin) and not visitedCoins[coin]
				and not isCoinNearMurderer(coin.Position)
			then
				local dist = (hrp.Position - coin.Position).Magnitude
				if dist < bestDist then bestDist = dist; nearest = coin end
			end
		end
	end
	return nearest
end

local function isRoundActive()
	local coinContainer = findActiveCoinContainer()
	if not coinContainer then return false end
	for _, coin in ipairs(coinContainer:GetChildren()) do
		if coin:IsA("BasePart") and coin.Name == "Coin_Server" and coin:FindFirstChild("CoinVisual") then
			return true
		end
	end
	return false
end

local function allCoinsGone()
	local coinContainer = findActiveCoinContainer()
	if not coinContainer then return true end
	for _, coin in ipairs(coinContainer:GetChildren()) do
		if coin:IsA("BasePart") and coin.Name == "Coin_Server" and coin:FindFirstChild("CoinVisual") then
			return false
		end
	end
	return true
end

local function getActiveMap()
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and obj:FindFirstChild("Spawns") and not obj.Name:lower():find("lobby") then
			return obj
		end
	end
	return nil
end

local function killCharacter()
	local char = localplayer.Character
	if char then
		local hum = char:FindFirstChild("Humanoid")
		if hum then hum.Health = 0 end
	end
end

local function waitForNewMapToLoad()
	waitingForNewMap = true
	local oldMap = getActiveMap()
	while getActiveMap() == oldMap and oldMap and oldMap.Parent do task.wait(0.5) end
	local timeout = tick() + 60
	while not getActiveMap() and tick() < timeout do task.wait(0.5) end
	task.wait(2)
	waitingForNewMap = false
end

local function isPlayerSpectating()
	local char = localplayer.Character
	if not char then return true end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return true end
	local humanoid = char:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return true end
	if hrp.Position.Y > 400 and isRoundActive() then return true end
	return false
end

local function waitIfSpectatingMidRound()
	if not isRoundActive() then return end
	if not isPlayerSpectating() then return end
	isSpectatingMidRound = true
	while autoFarm and isRoundActive() do task.wait(0.5) end
	if autoFarm then waitForNewMapToLoad() end
	isSpectatingMidRound = false
	visitedCoins = {}
end

local function doNormalFarm(hrp)
	if not hrp or not hrp.Parent or deadUntilNextRound or waitingForNewMap then return end
	local coin = findNearestCoin(hrp)
	while coin and not coin:FindFirstChild("CoinVisual") do
		visitedCoins[coin] = true; coin = findNearestCoin(hrp)
	end
	if not (coin and isCoinValid(coin)) then return end
	task.wait()
	if not isCoinValid(coin) then return end
	visitedCoins[coin] = true
	local targetPos = Vector3.new(coin.Position.X, coin.Position.Y, coin.Position.Z)
	local tweenTime = math.max((hrp.Position - targetPos).Magnitude / tweenSpeed, 0.1)
	cancelActiveTween()
	activeTween = TweenService:Create(hrp, TweenInfo.new(tweenTime, Enum.EasingStyle.Linear), { CFrame = CFrame.new(targetPos) })
	local coinGone = false
	local watchConn
	watchConn = RunService.Heartbeat:Connect(function()
		if not isCoinValid(coin) then
			coinGone = true; cancelActiveTween()
			if watchConn then watchConn:Disconnect(); watchConn = nil end
		end
	end)
	activeTween:Play(); activeTween.Completed:Wait(); activeTween = nil
	if watchConn then watchConn:Disconnect(); watchConn = nil end
	if not coinGone and isCoinValid(coin) then hrp.CFrame = CFrame.new(targetPos); task.wait(0.05) end
end

local function handleRoundEnd(hrp)
	cancelActiveTween(); disableNoclip(); visitedCoins = {}
	removeInvisibleFloor(); anchorHRP(hrp, false); deadUntilNextRound = true
	
	-- Check if player has knife
	local hasKnife = false
	local char = localplayer.Character
	if char and char:FindFirstChild("Knife") then
		hasKnife = true
	end
	local backpackKnife = localplayer.Backpack and localplayer.Backpack:FindFirstChild("Knife")
	if backpackKnife then hasKnife = true end
	
	-- PRIORITY 1: Wait in Lobby (overrides everything else)
	if waitInLobbyEnabled then
		local char = localplayer.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then root.CFrame = LOBBY_POSITION end
		end
		return
	end
	
	-- PRIORITY 2: Has knife AND Kill All enabled → murder everyone
	if hasKnife and autoSlashEnabled then
		local char = localplayer.Character
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then root.CFrame = LOBBY_POSITION end
		task.wait(0.5)
		if not char:FindFirstChild("Knife") then
			local knife = localplayer.Backpack and localplayer.Backpack:FindFirstChild("Knife")
			if knife then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then hum:EquipTool(knife); task.wait(0.1) end
			end
		end
		enableAntiFling()
		if glueConnection then glueConnection:Disconnect(); glueConnection = nil end
		local affectedPlayers = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= localplayer and player.Character then
				local tHRP = player.Character:FindFirstChild("HumanoidRootPart")
				if tHRP then
					if not originalKillData[player] then
						local data = {}
						for _, obj in ipairs(player.Character:GetDescendants()) do
							if obj:IsA("BasePart") then
								data[obj] = { Transparency = obj.Transparency, CanCollide = obj.CanCollide, CFrame = obj.CFrame }
							end
						end
						originalKillData[player] = data
					end
					for _, part in ipairs(player.Character:GetDescendants()) do
						if part:IsA("BasePart") then part.Transparency = 1; part.CanCollide = false end
					end
					table.insert(affectedPlayers, player)
				end
			end
		end
		glueConnection = RunService.Heartbeat:Connect(function()
			local cc = localplayer.Character
			if not cc then return end
			local cr = cc:FindFirstChild("HumanoidRootPart")
			if not cr then return end
			local lv = cr.CFrame.LookVector; local rv = cr.CFrame.RightVector
			local idx = 0
			for _, player in ipairs(affectedPlayers) do
				if player.Character then
					local tHRP = player.Character:FindFirstChild("HumanoidRootPart")
					if tHRP then
						-- FIX: Players now stay much closer to you
						local offset = idx * 0.8
						local angle = math.rad(offset - (#affectedPlayers - 1) * 0.5)
						tHRP.CFrame = CFrame.new(cr.Position + lv * 2.0 + rv * math.sin(angle) * 1.2)
						for _, part in ipairs(player.Character:GetDescendants()) do
							if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
								part.CFrame = tHRP.CFrame * CFrame.new(tHRP.CFrame:PointToObjectSpace(part.Position))
							end
						end
						idx = idx + 1
					end
				end
			end
		end)
		char = localplayer.Character
		local knife = char and char:FindFirstChild("Knife")
		if knife and knife:FindFirstChild("Stab") then
			local startTime = tick()
			while tick() - startTime < 8 do
				pcall(function() knife.Stab:FireServer("Slash") end)
				task.wait(0.08)
			end
		end
		task.spawn(function()
			task.wait(8.5)
			if glueConnection then glueConnection:Disconnect(); glueConnection = nil end
			for player, data in pairs(originalKillData) do
				if player.Character then
					for obj, props in pairs(data) do
						if obj and obj.Parent then
							obj.Transparency = props.Transparency
							obj.CanCollide = props.CanCollide
							obj.CFrame = props.CFrame
						end
					end
				end
			end
			originalKillData = {}
			disableAntiFling()
		end)
		return
	end
	
	-- PRIORITY 3: No knife + Auto Reset ON → just die (no lobby teleport)
	if autoResetEnabled then
		killCharacter()
		return
	end
end

local function normalFarmMain(hrp)
	if not hrp or waitingForNewMap then return end
	while autoFarm and not deadUntilNextRound and not waitingForNewMap and farmMode == "Normal" do
		if not isRoundActive() or allCoinsGone() then handleRoundEnd(hrp); break end
		doNormalFarm(hrp); task.wait(0.05)
	end
end

local function doSafe2Farm(hrp)
	if not hrp or not hrp.Parent or deadUntilNextRound or waitingForNewMap then return end
	local coin = findNearestCoin(hrp)
	while coin and not coin:FindFirstChild("CoinVisual") do
		visitedCoins[coin] = true; coin = findNearestCoin(hrp)
	end
	if not (coin and isCoinValid(coin)) then return end
	task.wait()
	if not isCoinValid(coin) then return end
	visitedCoins[coin] = true
	anchorHRP(hrp, false)
	local deepPos = Vector3.new(coin.Position.X, coin.Position.Y + safe2UndergroundOffset, coin.Position.Z)
	local tweenTime = math.max((hrp.Position - deepPos).Magnitude / tweenSpeed, 0.1)
	enableNoclip(); createFloatingPad(); cancelActiveTween()
	activeTween = TweenService:Create(hrp, TweenInfo.new(tweenTime, Enum.EasingStyle.Linear), { CFrame = CFrame.new(deepPos) })
	local coinGone = false
	local watchConn
	watchConn = RunService.Heartbeat:Connect(function()
		if not isCoinValid(coin) then
			coinGone = true; cancelActiveTween()
			if watchConn then watchConn:Disconnect(); watchConn = nil end
		end
	end)
	activeTween:Play(); activeTween.Completed:Wait(); activeTween = nil
	if watchConn then watchConn:Disconnect(); watchConn = nil end
	disableNoclip(); removeInvisibleFloor(); forceServerSync(localplayer.Character)
	if coinGone then
		anchorHRP(hrp, true)
		local next = findNearestCoin(hrp)
		if next and isCoinValid(next) then doSafe2Farm(hrp) end
		return
	end
	if not isCoinValid(coin) then anchorHRP(hrp, true); return end
	local pickupPos = Vector3.new(coin.Position.X, coin.Position.Y + safe2PickupOffsetY, coin.Position.Z)
	setCharacterVisibility(false)
	hrp.CFrame = CFrame.new(pickupPos)
	task.wait(0.001)
	setCharacterVisibility(true)
	if not isCoinValid(coin) then hrp.CFrame = CFrame.new(deepPos); anchorHRP(hrp, true); return end
	hrp.CFrame = CFrame.new(deepPos); anchorHRP(hrp, true)
end

local function safeFarmMain(hrp)
	if not hrp or waitingForNewMap then return end
	anchorHRP(hrp, false); forceServerSync(localplayer.Character); anchorHRP(hrp, true)
	while autoFarm and not deadUntilNextRound and not waitingForNewMap and farmMode == "Underground" do
		if not isRoundActive() or allCoinsGone() then handleRoundEnd(hrp); break end
		doSafe2Farm(hrp); task.wait(0.05)
	end
	removeInvisibleFloor(); anchorHRP(hrp, false)
end

local function customDeathHandler()
	deadUntilNextRound = true; cancelActiveTween(); disableNoclip()
	visitedCoins = {}; removeInvisibleFloor(); disableAntiFling()
	if glueConnection then glueConnection:Disconnect(); glueConnection = nil end
	if localplayer.Character and localplayer.Character:FindFirstChild("HumanoidRootPart") then
		localplayer.Character.HumanoidRootPart.Anchored = false
	end
end

local function enableAntiAfk()
	if antiAfkConnection then return end
	antiAfkConnection = localplayer.Idled:Connect(function()
		if not antiAfkEnabled then return end
		pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
	end)
	task.spawn(function()
		while antiAfkConnection do
			task.wait(60)
			if antiAfkEnabled then
				pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
			end
		end
	end)
end

local function startFarmLoop()
	if farmLoopRunning then return end
	farmLoopRunning = true
	enableAntiFling()
	task.spawn(function()
		waitIfSpectatingMidRound()
		if not autoFarm then farmLoopRunning = false; return end
		while autoFarm do
			if deadUntilNextRound then
				local char = localplayer.Character
				if not char or not char:FindFirstChild("HumanoidRootPart") then
					localplayer.CharacterAdded:Wait(); task.wait(0.5)
				end
				waitForNewMapToLoad(); deadUntilNextRound = false; visitedCoins = {}
				task.wait(1); task.wait(0.3); continue
			end
			local char = localplayer.Character
			if not char then task.wait(0.5); continue end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			local humanoid = char:FindFirstChild("Humanoid")
			if humanoid then
				if humanoidDiedConn then pcall(function() humanoidDiedConn:Disconnect() end) end
				humanoidDiedConn = humanoid.Died:Connect(customDeathHandler)
			end
			if not hrp or not humanoid or humanoid.Health <= 0 or deadUntilNextRound or waitingForNewMap then
				task.wait(0.5); continue
			end
			local waitStart = tick()
			while autoFarm and not isRoundActive() and not deadUntilNextRound do
				task.wait(0.1)
				if tick() - waitStart > 90 then break end
			end
			if not autoFarm or deadUntilNextRound then task.wait(0.2); continue end
			char = localplayer.Character
			if not char then task.wait(0.5); continue end
			hrp = char:FindFirstChild("HumanoidRootPart")
			humanoid = char:FindFirstChild("Humanoid")
			if not hrp or not humanoid or humanoid.Health <= 0 then task.wait(0.5); continue end
			local coin = findNearestCoin(hrp)
			if farmMode == "Underground" and coin and isCoinValid(coin) then
				hrp.CFrame = CFrame.new(coin.Position.X, coin.Position.Y + safe2UndergroundOffset, coin.Position.Z)
				forceServerSync(char); task.wait(0.1)
			end
			if farmMode == "Underground" then safeFarmMain(hrp) else normalFarmMain(hrp) end
		end
		farmLoopRunning = false; disableAntiFling()
	end)
end

localplayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	local char = localplayer.Character
	if not char then return end
	local humanoid = char:FindFirstChild("Humanoid")
	if humanoid then
		if humanoidDiedConn then humanoidDiedConn:Disconnect() end
		humanoidDiedConn = humanoid.Died:Connect(customDeathHandler)
	end
end)

Workspace.ChildAdded:Connect(function(child)
	if not autoFarm or deadUntilNextRound then return end
	if child:IsA("Model") and not child.Name:lower():find("lobby") and child:FindFirstChild("Spawns") then
		task.spawn(function()
			task.wait(2)
			if autoFarm and not deadUntilNextRound and not waitingForNewMap then
				local char = localplayer.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local mapModel = getActiveMap()
				if hrp and mapModel then
					local spawnsFolder = mapModel:FindFirstChild("Spawns")
					if spawnsFolder then
						local pts = spawnsFolder:GetChildren()
						if #pts > 0 then
							hrp.CFrame = CFrame.new(pts[math.random(1, #pts)].Position + Vector3.new(0, 3, 0))
							forceServerSync(char)
						end
					end
				end
			end
		end)
	end
end)

local Weapons = {}
local PlayerData = {}
pcall(function() Weapons = require(game:GetService("ReplicatedStorage").Database.Sync.Item) end)
pcall(function() PlayerData = require(game:GetService("ReplicatedStorage").Modules.ProfileData) end)

local sg = Instance.new("ScreenGui")
sg.Name = "MM2Farm"; sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.IgnoreGuiInset = true
sg.Parent = game.CoreGui

local reopenBar = Instance.new("Frame")
reopenBar.Size = UDim2.new(0, 130, 0, 26)
reopenBar.Position = UDim2.new(0.5, -65, 0, 6)
reopenBar.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
reopenBar.BorderSizePixel = 0
reopenBar.Visible = false
reopenBar.ZIndex = 50
reopenBar.Active = true
reopenBar.Parent = sg
Instance.new("UICorner", reopenBar).CornerRadius = UDim.new(0, 6)
local rbStroke = Instance.new("UIStroke", reopenBar)
rbStroke.Color = Color3.fromRGB(45, 45, 45); rbStroke.Thickness = 1

local reopenBtn = Instance.new("TextButton")
reopenBtn.Size = UDim2.new(1,0,1,0); reopenBtn.BackgroundTransparency = 1
reopenBtn.Text = "▼  MM2 Farm"; reopenBtn.TextColor3 = Color3.fromRGB(160,160,160)
reopenBtn.TextSize = 11; reopenBtn.Font = Enum.Font.GothamMedium
reopenBtn.ZIndex = 51; reopenBtn.Parent = reopenBar

local W, H = 300, 370

local main = Instance.new("Frame")
main.Size = UDim2.new(0, W, 0, H)
main.Position = UDim2.new(0.5, -W/2, 0.08, 0)
main.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
main.BorderSizePixel = 0
main.Active = true
main.Parent = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = Color3.fromRGB(40, 40, 40); mainStroke.Thickness = 1

local titleH = 36
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, titleH)
titleBar.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
titleBar.BorderSizePixel = 0
titleBar.ZIndex = 3
titleBar.Parent = main
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0.5, 0)
titleFix.Position = UDim2.new(0, 0, 0.5, 0)
titleFix.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
titleFix.BorderSizePixel = 0; titleFix.Parent = titleBar

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -80, 1, 0)
titleLbl.Position = UDim2.new(0, 14, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "MM2 Auto Farm"
titleLbl.TextColor3 = Color3.fromRGB(185, 185, 185)
titleLbl.TextSize = 13; titleLbl.Font = Enum.Font.GothamMedium
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.ZIndex = 4; titleLbl.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -30, 0.5, -12)
closeBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
closeBtn.BorderSizePixel = 0; closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(120, 120, 120)
closeBtn.TextSize = 11; closeBtn.Font = Enum.Font.GothamBold
closeBtn.ZIndex = 5; closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

local SIDEBAR_W = 72
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -titleH)
body.Position = UDim2.new(0, 0, 0, titleH)
body.BackgroundTransparency = 1
body.ClipsDescendants = true
body.Parent = main

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, 0)
sidebar.Position = UDim2.new(0, 0, 0, 0)
sidebar.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
sidebar.BorderSizePixel = 0
sidebar.ClipsDescendants = true
sidebar.Parent = body

local sideCorner = Instance.new("UICorner", sidebar)
sideCorner.CornerRadius = UDim.new(0, 10)
local sideFix = Instance.new("Frame", sidebar)
sideFix.Size = UDim2.new(0.5, 0, 1, 0)
sideFix.Position = UDim2.new(0.5, 0, 0, 0)
sideFix.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
sideFix.BorderSizePixel = 0

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -SIDEBAR_W - 1, 1, -8)
content.Position = UDim2.new(0, SIDEBAR_W + 1, 0, 4)
content.BackgroundTransparency = 1
content.ClipsDescendants = true; content.Parent = body

local tabBtns = {}
local tabPages = {}
local tabAccents = {}

local TAB_H = 46
local TAB_PAD = 8
local TAB_GAP = 4

local function makeTabBtn(label, idx)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -12, 0, TAB_H)
	btn.Position = UDim2.new(0, 6, 0, TAB_PAD + (idx - 1) * (TAB_H + TAB_GAP))
	btn.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
	btn.BorderSizePixel = 0
	btn.Text = label
	btn.TextColor3 = Color3.fromRGB(70, 70, 70)
	btn.TextSize = 9; btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = false
	btn.TextWrapped = true
	btn.Parent = sidebar
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	local stroke = Instance.new("UIStroke", btn)
	stroke.Color = Color3.fromRGB(30, 30, 30); stroke.Thickness = 1
	local accent = Instance.new("Frame", btn)
	accent.Size = UDim2.new(0, 2, 0.5, 0)
	accent.AnchorPoint = Vector2.new(1, 0.5)
	accent.Position = UDim2.new(1, 0, 0.5, 0)
	accent.BackgroundColor3 = Color3.fromRGB(190, 190, 190)
	accent.BorderSizePixel = 0
	accent.Visible = false
	Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)
	return btn, accent
end

local function switchTab(name)
	for n, page in pairs(tabPages) do page.Visible = (n == name) end
	for n, btn in pairs(tabBtns) do
		local active = (n == name)
		TweenService:Create(btn, TweenInfo.new(0.1), {
			BackgroundColor3 = active and Color3.fromRGB(32, 32, 32) or Color3.fromRGB(22, 22, 22),
			TextColor3 = active and Color3.fromRGB(220, 220, 220) or Color3.fromRGB(70, 70, 70),
		}):Play()
		if tabAccents[n] then tabAccents[n].Visible = active end
	end
end

local function makePage()
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 2
	scroll.ScrollBarImageColor3 = Color3.fromRGB(50, 50, 50)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Visible = false; scroll.Parent = content
	local list = Instance.new("UIListLayout", scroll)
	list.FillDirection = Enum.FillDirection.Vertical
	list.Padding = UDim.new(0, 0); list.SortOrder = Enum.SortOrder.LayoutOrder
	local pad = Instance.new("UIPadding", scroll)
	pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 6)
	return scroll
end

local farmTab, farmAccent = makeTabBtn("AUTO\nFARM", 1)
local weapTab, weapAccent = makeTabBtn("WEAPON\nSPAWN", 2)
tabBtns["farm"] = farmTab; tabBtns["weapon"] = weapTab
tabAccents["farm"] = farmAccent; tabAccents["weapon"] = weapAccent

local farmPage = makePage(); tabPages["farm"] = farmPage
local weapPage = makePage(); tabPages["weapon"] = weapPage

farmTab.MouseButton1Click:Connect(function() switchTab("farm") end)
weapTab.MouseButton1Click:Connect(function() switchTab("weapon") end)

local function makeSection(parent, text, order)
	local wrap = Instance.new("Frame")
	wrap.Size = UDim2.new(1, 0, 0, 22)
	wrap.BackgroundTransparency = 1; wrap.LayoutOrder = order; wrap.Parent = parent
	local lbl = Instance.new("TextLabel", wrap)
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1; lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(65, 65, 65)
	lbl.TextSize = 9; lbl.Font = Enum.Font.GothamBold
	lbl.TextXAlignment = Enum.TextXAlignment.Left
end

local function makeDivider(parent, order)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 1)
	f.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
	f.BorderSizePixel = 0; f.LayoutOrder = order; f.Parent = parent
end

local function makeToggle(parent, label, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 38)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order; row.Parent = parent

	local lbl = Instance.new("TextLabel", row)
	lbl.Size = UDim2.new(1, -54, 1, 0)
	lbl.BackgroundTransparency = 1; lbl.Text = label
	lbl.TextColor3 = Color3.fromRGB(175, 175, 175)
	lbl.TextSize = 12; lbl.Font = Enum.Font.Gotham
	lbl.TextXAlignment = Enum.TextXAlignment.Left

	local track = Instance.new("TextButton", row)
	track.Size = UDim2.new(0, 44, 0, 24)
	track.Position = UDim2.new(1, -44, 0.5, -12)
	track.BackgroundColor3 = Color3.fromRGB(36, 36, 36)
	track.BorderSizePixel = 0; track.Text = ""; track.AutoButtonColor = false
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local ts = Instance.new("UIStroke", track); ts.Color = Color3.fromRGB(50,50,50); ts.Thickness = 1

	local knob = Instance.new("Frame", track)
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.Position = UDim2.new(0, 3, 0.5, -9)
	knob.BackgroundColor3 = Color3.fromRGB(80, 80, 80); knob.BorderSizePixel = 0
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	return track, knob
end

local function setToggle(track, knob, state)
	TweenService:Create(track, TweenInfo.new(0.14), {
		BackgroundColor3 = state and Color3.fromRGB(55,55,55) or Color3.fromRGB(36,36,36)
	}):Play()
	TweenService:Create(knob, TweenInfo.new(0.14), {
		Position = state and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9),
		BackgroundColor3 = state and Color3.fromRGB(220,220,220) or Color3.fromRGB(80,80,80)
	}):Play()
end

makeSection(farmPage, "AUTO FARM", 1)
local farmTrack, farmKnob = makeToggle(farmPage, "Auto Farm", 2)

local modeRow = Instance.new("Frame")
modeRow.Size = UDim2.new(1, 0, 0, 38)
modeRow.BackgroundTransparency = 1; modeRow.LayoutOrder = 3; modeRow.Parent = farmPage

local modeLbl = Instance.new("TextLabel", modeRow)
modeLbl.Size = UDim2.new(0.45, 0, 1, 0)
modeLbl.BackgroundTransparency = 1; modeLbl.Text = "Mode"
modeLbl.TextColor3 = Color3.fromRGB(175, 175, 175)
modeLbl.TextSize = 12; modeLbl.Font = Enum.Font.Gotham
modeLbl.TextXAlignment = Enum.TextXAlignment.Left

local modeBtn = Instance.new("TextButton", modeRow)
modeBtn.Size = UDim2.new(0, 100, 0, 24)
modeBtn.Position = UDim2.new(1, -102, 0.5, -12)
modeBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
modeBtn.BorderSizePixel = 0; modeBtn.Text = "Select  ▾"
modeBtn.TextColor3 = Color3.fromRGB(155, 155, 155)
modeBtn.TextSize = 11; modeBtn.Font = Enum.Font.GothamMedium
modeBtn.AutoButtonColor = false
Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0, 6)
local mbs = Instance.new("UIStroke", modeBtn); mbs.Color = Color3.fromRGB(45,45,45); mbs.Thickness = 1

local modeDrop = Instance.new("Frame")
modeDrop.Size = UDim2.new(0, 102, 0, 52)
modeDrop.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
modeDrop.BorderSizePixel = 0; modeDrop.Visible = false
modeDrop.ZIndex = 30; modeDrop.Parent = main
Instance.new("UICorner", modeDrop).CornerRadius = UDim.new(0, 7)
local mds = Instance.new("UIStroke", modeDrop); mds.Color = Color3.fromRGB(45,45,45); mds.Thickness = 1

for i, opt in ipairs({"Normal","Underground"}) do
	local b = Instance.new("TextButton", modeDrop)
	b.Size = UDim2.new(1, 0, 0, 26); b.Position = UDim2.new(0, 0, 0, (i-1)*26)
	b.BackgroundTransparency = 1; b.Text = opt
	b.TextColor3 = Color3.fromRGB(170, 170, 170)
	b.TextSize = 11; b.Font = Enum.Font.Gotham; b.ZIndex = 31
	b.TextXAlignment = Enum.TextXAlignment.Left
	local bp = Instance.new("UIPadding", b); bp.PaddingLeft = UDim.new(0, 10)
	b.MouseEnter:Connect(function() b.BackgroundTransparency = 0; b.BackgroundColor3 = Color3.fromRGB(30,30,30) end)
	b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
	b.MouseButton1Click:Connect(function()
		farmMode = opt; modeBtn.Text = opt .. "  ▾"; modeDrop.Visible = false
		if autoFarm then
			cancelActiveTween(); disableNoclip(); removeInvisibleFloor()
			local char = localplayer.Character
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then hrp.Anchored = false end
			end
		end
	end)
end

modeBtn.MouseButton1Click:Connect(function()
	modeDrop.Visible = not modeDrop.Visible
	if modeDrop.Visible then
		local ap = modeBtn.AbsolutePosition; local mp = main.AbsolutePosition
		modeDrop.Position = UDim2.new(0, ap.X - mp.X, 0, ap.Y - mp.Y + 26)
	end
end)

makeDivider(farmPage, 4)
makeSection(farmPage, "AT FULL COINS", 5)
local resetTrack, resetKnob = makeToggle(farmPage, "Auto Reset", 6)
local slashTrack, slashKnob = makeToggle(farmPage, "Kill All (Murder)", 7)
local lobbyTrack, lobbyKnob = makeToggle(farmPage, "Wait in Lobby", 8)

makeDivider(farmPage, 9)
makeSection(farmPage, "SETTINGS", 10)
local afkTrack, afkKnob = makeToggle(farmPage, "Anti AFK", 11)
local avoidTrack, avoidKnob = makeToggle(farmPage, "Avoid Murderer Coins", 12)

local speedWrap = Instance.new("Frame")
speedWrap.Size = UDim2.new(1, 0, 0, 50)
speedWrap.BackgroundTransparency = 1; speedWrap.LayoutOrder = 13; speedWrap.Parent = farmPage

local speedLbl = Instance.new("TextLabel", speedWrap)
speedLbl.Size = UDim2.new(0.65, 0, 0, 18); speedLbl.BackgroundTransparency = 1
speedLbl.Text = "Tween Speed"; speedLbl.TextColor3 = Color3.fromRGB(155,155,155)
speedLbl.TextSize = 11; speedLbl.Font = Enum.Font.Gotham; speedLbl.TextXAlignment = Enum.TextXAlignment.Left

local speedVal = Instance.new("TextLabel", speedWrap)
speedVal.Size = UDim2.new(0.35, 0, 0, 18); speedVal.Position = UDim2.new(0.65, 0, 0, 0)
speedVal.BackgroundTransparency = 1; speedVal.Text = tostring(tweenSpeed)
speedVal.TextColor3 = Color3.fromRGB(185,185,185); speedVal.TextSize = 11
speedVal.Font = Enum.Font.GothamMedium; speedVal.TextXAlignment = Enum.TextXAlignment.Right

local sTrack = Instance.new("Frame", speedWrap)
sTrack.Size = UDim2.new(1, 0, 0, 4); sTrack.Position = UDim2.new(0, 0, 0, 30)
sTrack.BackgroundColor3 = Color3.fromRGB(36, 36, 36); sTrack.BorderSizePixel = 0
Instance.new("UICorner", sTrack).CornerRadius = UDim.new(1, 0)

local sFill = Instance.new("Frame", sTrack)
sFill.Size = UDim2.new(tweenSpeed/30, 0, 1, 0)
sFill.BackgroundColor3 = Color3.fromRGB(95,95,95); sFill.BorderSizePixel = 0
Instance.new("UICorner", sFill).CornerRadius = UDim.new(1, 0)

local sKnob = Instance.new("Frame", sTrack)
sKnob.Size = UDim2.new(0, 14, 0, 14); sKnob.AnchorPoint = Vector2.new(0.5, 0.5)
sKnob.Position = UDim2.new(tweenSpeed/30, 0, 0.5, 0)
sKnob.BackgroundColor3 = Color3.fromRGB(200,200,200); sKnob.BorderSizePixel = 0
Instance.new("UICorner", sKnob).CornerRadius = UDim.new(1, 0)

local sHit = Instance.new("TextButton", sTrack)
sHit.Size = UDim2.new(1, 0, 0, 24); sHit.Position = UDim2.new(0,0,0.5,-12)
sHit.BackgroundTransparency = 1; sHit.Text = ""

local sliding = false
local function updateSlider(x)
	local rel = math.clamp((x - sTrack.AbsolutePosition.X) / sTrack.AbsoluteSize.X, 0, 1)
	local spd = math.max(math.round(rel * 30), 1)
	tweenSpeed = spd; speedVal.Text = tostring(spd)
	sFill.Size = UDim2.new(rel, 0, 1, 0)
	sKnob.Position = UDim2.new(rel, 0, 0.5, 0)
end

sHit.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		sliding = true; updateSlider(i.Position.X)
	end
end)
sHit.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		sliding = false
	end
end)
UserInputService.InputChanged:Connect(function(i)
	if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		updateSlider(i.Position.X)
	end
end)

makeSection(weapPage, "WEAPON SPAWNER", 1)

local wSearchBox = Instance.new("TextBox")
wSearchBox.Size = UDim2.new(1, 0, 0, 34)
wSearchBox.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
wSearchBox.BorderSizePixel = 0; wSearchBox.Text = ""
wSearchBox.PlaceholderText = "Search weapon..."
wSearchBox.TextColor3 = Color3.fromRGB(185,185,185)
wSearchBox.PlaceholderColor3 = Color3.fromRGB(65,65,65)
wSearchBox.TextSize = 12; wSearchBox.Font = Enum.Font.Gotham
wSearchBox.ClearTextOnFocus = false
wSearchBox.TextXAlignment = Enum.TextXAlignment.Left
wSearchBox.LayoutOrder = 2; wSearchBox.Parent = weapPage
Instance.new("UICorner", wSearchBox).CornerRadius = UDim.new(0, 7)
local wbs = Instance.new("UIStroke", wSearchBox); wbs.Color = Color3.fromRGB(42,42,42); wbs.Thickness = 1
local wbp = Instance.new("UIPadding", wSearchBox); wbp.PaddingLeft = UDim.new(0,10); wbp.PaddingRight = UDim.new(0,10)

local wDrop = Instance.new("ScrollingFrame")
wDrop.Size = UDim2.new(1, 0, 0, 0)
wDrop.BackgroundColor3 = Color3.fromRGB(20,20,20); wDrop.BorderSizePixel = 0
wDrop.Visible = false; wDrop.LayoutOrder = 3
wDrop.CanvasSize = UDim2.new(0,0,0,0); wDrop.ScrollBarThickness = 2
wDrop.ScrollBarImageColor3 = Color3.fromRGB(50,50,50); wDrop.ClipsDescendants = true
wDrop.Parent = weapPage
Instance.new("UICorner", wDrop).CornerRadius = UDim.new(0, 6)
local wds = Instance.new("UIStroke", wDrop); wds.Color = Color3.fromRGB(40,40,40); wds.Thickness = 1
Instance.new("UIListLayout", wDrop).SortOrder = Enum.SortOrder.Name

local amtRow = Instance.new("Frame")
amtRow.Size = UDim2.new(1,0,0,38); amtRow.BackgroundTransparency = 1
amtRow.LayoutOrder = 4; amtRow.Parent = weapPage

local amtLbl = Instance.new("TextLabel", amtRow)
amtLbl.Size = UDim2.new(0.5,0,1,0); amtLbl.BackgroundTransparency = 1
amtLbl.Text = "Amount"; amtLbl.TextColor3 = Color3.fromRGB(175,175,175)
amtLbl.TextSize = 12; amtLbl.Font = Enum.Font.Gotham; amtLbl.TextXAlignment = Enum.TextXAlignment.Left

local amtBox = Instance.new("TextBox", amtRow)
amtBox.Size = UDim2.new(0, 70, 0, 26); amtBox.Position = UDim2.new(1,-72,0.5,-13)
amtBox.BackgroundColor3 = Color3.fromRGB(22,22,22); amtBox.BorderSizePixel = 0
amtBox.Text = "1"; amtBox.TextColor3 = Color3.fromRGB(185,185,185)
amtBox.TextSize = 12; amtBox.Font = Enum.Font.GothamMedium
amtBox.ClearTextOnFocus = false; amtBox.TextXAlignment = Enum.TextXAlignment.Center
Instance.new("UICorner", amtBox).CornerRadius = UDim.new(0, 6)
local abs2 = Instance.new("UIStroke", amtBox); abs2.Color = Color3.fromRGB(42,42,42); abs2.Thickness = 1

local spawnBtn = Instance.new("TextButton")
spawnBtn.Size = UDim2.new(1,0,0,34); spawnBtn.LayoutOrder = 5
spawnBtn.BackgroundColor3 = Color3.fromRGB(26,26,26); spawnBtn.BorderSizePixel = 0
spawnBtn.Text = "Spawn Weapon"; spawnBtn.TextColor3 = Color3.fromRGB(175,175,175)
spawnBtn.TextSize = 12; spawnBtn.Font = Enum.Font.GothamMedium; spawnBtn.AutoButtonColor = false
spawnBtn.Parent = weapPage
Instance.new("UICorner", spawnBtn).CornerRadius = UDim.new(0, 7)
local sps = Instance.new("UIStroke", spawnBtn); sps.Color = Color3.fromRGB(45,45,45); sps.Thickness = 1

local wStatus = Instance.new("TextLabel")
wStatus.Size = UDim2.new(1,0,0,20); wStatus.LayoutOrder = 6
wStatus.BackgroundTransparency = 1; wStatus.Text = ""
wStatus.TextColor3 = Color3.fromRGB(120,185,120)
wStatus.TextSize = 11; wStatus.Font = Enum.Font.Gotham; wStatus.Parent = weapPage

local wStTh
local function showStatus(txt, col)
	wStatus.Text = txt; wStatus.TextColor3 = col or Color3.fromRGB(120,185,120)
	if wStTh then task.cancel(wStTh) end
	wStTh = task.delay(2.5, function() wStatus.Text = "" end)
end

local function getAmt()
	local n = tonumber(amtBox.Text)
	if not n or n < 1 then n = 1; amtBox.Text = "1" end
	return math.floor(n)
end

local function popWeapDrop(query)
	for _, c in ipairs(wDrop:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	if not query or query == "" then wDrop.Visible = false; return end
	local hits, q = {}, query:lower()
	for name in pairs(Weapons) do
		if name:lower():find(q, 1, true) then table.insert(hits, name) end
	end
	if #hits == 0 then wDrop.Visible = false; return end
	local IH = 26; local show = math.min(#hits, 5)
	wDrop.Size = UDim2.new(1, 0, 0, show * IH)
	wDrop.CanvasSize = UDim2.new(0, 0, 0, #hits * IH)
	wDrop.Visible = true
	for _, name in ipairs(hits) do
		local b = Instance.new("TextButton", wDrop)
		b.Size = UDim2.new(1, 0, 0, IH); b.BackgroundTransparency = 1
		b.Text = name; b.TextColor3 = Color3.fromRGB(165,165,165)
		b.TextSize = 11; b.Font = Enum.Font.Gotham; b.BorderSizePixel = 0
		b.AutoButtonColor = false; b.ZIndex = 5; b.TextXAlignment = Enum.TextXAlignment.Left
		local bp2 = Instance.new("UIPadding", b); bp2.PaddingLeft = UDim.new(0,8)
		b.MouseEnter:Connect(function() b.BackgroundTransparency = 0; b.BackgroundColor3 = Color3.fromRGB(28,28,28) end)
		b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
		b.MouseButton1Click:Connect(function() wSearchBox.Text = name; wDrop.Visible = false end)
	end
end

local function resolveWeap(input)
	local low = input:lower()
	for name in pairs(Weapons) do if name:lower() == low then return name end end
end

local function doSpawn()
	local exact = resolveWeap(wSearchBox.Text)
	if not exact then showStatus("not found: " .. wSearchBox.Text, Color3.fromRGB(185,90,90)); return end
	local amt = getAmt()
	local owned = (PlayerData.Weapons and PlayerData.Weapons.Owned) or {}
	local new = {}; for k,v in pairs(owned) do new[k] = v end
	new[exact] = (new[exact] or 0) + amt
	if PlayerData.Weapons then PlayerData.Weapons.Owned = new end
	if localplayer.Character then localplayer.Character:BreakJoints() end
	showStatus("spawned " .. exact .. " ×" .. amt)
end

wSearchBox:GetPropertyChangedSignal("Text"):Connect(function() popWeapDrop(wSearchBox.Text) end)
spawnBtn.MouseButton1Click:Connect(function()
	if wSearchBox.Text ~= "" then doSpawn() end; wDrop.Visible = false
end)
spawnBtn.MouseEnter:Connect(function() spawnBtn.BackgroundColor3 = Color3.fromRGB(32,32,32) end)
spawnBtn.MouseLeave:Connect(function() spawnBtn.BackgroundColor3 = Color3.fromRGB(26,26,26) end)

farmTrack.MouseButton1Click:Connect(function()
	if not farmMode then return end
	autoFarm = not autoFarm; setToggle(farmTrack, farmKnob, autoFarm)
	if autoFarm then
		deadUntilNextRound = false; visitedCoins = {}; startFarmLoop()
	else
		cancelActiveTween(); disableNoclip(); removeInvisibleFloor()
		disableAntiFling()
		if glueConnection then glueConnection:Disconnect(); glueConnection = nil end
		local char = localplayer.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then hrp.Anchored = false end
		end
	end
end)

resetTrack.MouseButton1Click:Connect(function()
	autoResetEnabled = not autoResetEnabled; setToggle(resetTrack, resetKnob, autoResetEnabled)
end)

slashTrack.MouseButton1Click:Connect(function()
	autoSlashEnabled = not autoSlashEnabled; setToggle(slashTrack, slashKnob, autoSlashEnabled)
end)

lobbyTrack.MouseButton1Click:Connect(function()
	waitInLobbyEnabled = not waitInLobbyEnabled; setToggle(lobbyTrack, lobbyKnob, waitInLobbyEnabled)
end)

afkTrack.MouseButton1Click:Connect(function()
	antiAfkEnabled = not antiAfkEnabled; setToggle(afkTrack, afkKnob, antiAfkEnabled)
	if antiAfkEnabled then enableAntiAfk()
	else
		if antiAfkConnection then antiAfkConnection:Disconnect(); antiAfkConnection = nil end
	end
end)

avoidTrack.MouseButton1Click:Connect(function()
	avoidMurderCoins = not avoidMurderCoins; setToggle(avoidTrack, avoidKnob, avoidMurderCoins)
end)

closeBtn.MouseButton1Click:Connect(function()
	main.Visible = false; reopenBar.Visible = true
end)
reopenBtn.MouseButton1Click:Connect(function()
	reopenBar.Visible = false; main.Visible = true
end)

local function makeDraggable(handle, target)
	local dragging = false
	local dragOffX, dragOffY = 0, 0
	handle.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1
			and i.UserInputType ~= Enum.UserInputType.Touch then return end
		dragging = true
		local mp = UserInputService:GetMouseLocation()
		dragOffX = mp.X - target.AbsolutePosition.X
		dragOffY = mp.Y - target.AbsolutePosition.Y
	end)
	UserInputService.InputChanged:Connect(function(i)
		if not dragging then return end
		if i.UserInputType ~= Enum.UserInputType.MouseMovement
			and i.UserInputType ~= Enum.UserInputType.Touch then return end
		local mp = UserInputService:GetMouseLocation()
		local vp = workspace.CurrentCamera.ViewportSize
		target.Position = UDim2.fromOffset(
			math.clamp(mp.X - dragOffX, 0, vp.X - target.AbsoluteSize.X),
			math.clamp(mp.Y - dragOffY, 0, vp.Y - target.AbsoluteSize.Y)
		)
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
			or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

makeDraggable(titleBar, main)
makeDraggable(reopenBar, reopenBar)

UserInputService.InputBegan:Connect(function(inp)
	if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	local mp = inp.Position
	local function out(f)
		local p, s = f.AbsolutePosition, f.AbsoluteSize
		return not (mp.X >= p.X and mp.X <= p.X+s.X and mp.Y >= p.Y and mp.Y <= p.Y+s.Y)
	end
	if modeDrop.Visible and out(modeDrop) and out(modeBtn) then modeDrop.Visible = false end
	if wDrop.Visible and out(wDrop) and out(wSearchBox) then wDrop.Visible = false end
end)

switchTab("farm")
