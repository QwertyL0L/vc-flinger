-- credits:
-- me (QwertyL0L) for putting it all together (and yes ik my code prolly looks like crap but im still learning lua so ye)
-- IY for the fling, unfling, getRoot code
-- random dev forum post for vc listening code (modified a bit by me tho)


local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

local toggle = false
local ToggleKey = Enum.KeyCode.Z -- change "Z" to whatever

local targetName = "All" -- either "All" or a specific player's username (didnt really test specific users tho lmao)
local connected = {}
local trackingConnections = {}
local tpDuration = 0.1
local flungRecently = false

local function getRoot(char)
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

local function canFlingPlayers()
	for _, part in ipairs(Character:GetChildren()) do
		if part:IsA("BasePart") then
			local groupId = part.CollisionGroupId
			local groupName = PhysicsService:GetCollisionGroupName(groupId)

			if PhysicsService:CollisionGroupsAreCollidable(groupName, "Default") then
				return true
			end
		end
	end

	return false
end

local function fling()
	local character = LocalPlayer.Character
	if not character then return end

	local root = getRoot(character)
	if not root then return end

	-- Set your own character parts to fling-friendly values
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5)
			part.CanCollide = false
			part.Massless = true
			part.Velocity = Vector3.new(0, 0, 0)
		end
	end

	-- Create angular velocity on your root part
	local bav = Instance.new("BodyAngularVelocity")
	bav.Name = "Flinging"
	bav.AngularVelocity = Vector3.new(0, 99999, 0)
	bav.MaxTorque = Vector3.new(0, math.huge, 0)
	bav.P = math.huge
	bav.Parent = root

	task.spawn(function()
		local elapsed = 0
		while elapsed < tpDuration and toggle do
			if bav and bav.Parent then
				bav.AngularVelocity = Vector3.new(0, 99999, 0)
				task.wait(0.2)
				bav.AngularVelocity = Vector3.zero
				task.wait(0.1)
				elapsed += 0.3
			else
				break
			end
		end
	end)

end

local function unfling()
	local character = LocalPlayer.Character
	if not character then return end

	local root = getRoot(character)
	if root then
		for _, v in pairs(root:GetChildren()) do
			if v:IsA("BodyAngularVelocity") then
				v:Destroy()
			end
		end
	end

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5)
			part.CanCollide = true
			part.Massless = false
		end
	end
end

local function getOriginalCFrame(rootPart)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

    -- Cast downward (most important)
    local downResult = workspace:Raycast(rootPart.Position, Vector3.new(0, -500, 0), raycastParams)
    if downResult and downResult.Position then
        local safePos = downResult.Position + Vector3.new(0, rootPart.Size.Y / 2 + 0.5, 0)
        return CFrame.new(safePos)
    end

    -- If no ground found below, cast upward (in case on a platform ceiling)
    local upResult = workspace:Raycast(rootPart.Position, Vector3.new(0, 500, 0), raycastParams)
    if upResult and upResult.Position then
        local safePos = upResult.Position - Vector3.new(0, rootPart.Size.Y / 2 + 0.5, 0)
        return CFrame.new(safePos)
    end

    -- Fallback: use current X,Z, and a safe Y height (e.g., 50)
    local fallbackPos = Vector3.new(rootPart.Position.X, 50, rootPart.Position.Z)
    return CFrame.new(fallbackPos)
end

local function listenAndTeleport(player)
    if connected[player] then return end
    if player == LocalPlayer then return end

    local input = player:FindFirstChild("AudioDeviceInput")
    if not input then
        warn("No AudioDeviceInput for", player.Name)
        return
    end

    local analyzer = Instance.new("AudioAnalyzer")
    analyzer.Name = "VoiceAnalyzer_" .. player.Name
    analyzer.Parent = workspace

    local wire = Instance.new("Wire")
    wire.SourceInstance = input
    wire.TargetInstance = analyzer
    wire.Parent = analyzer

    local conn
    conn = RunService.RenderStepped:Connect(function()
        if analyzer.Parent == nil then
            conn:Disconnect()
            return
        end

        if analyzer.RmsLevel > 0 and not flungRecently then
            flungRecently = true

            local rootPart = getRoot(LocalPlayer.Character)
            local targetRoot = getRoot(player.Character)
            local originalCFrame = getOriginalCFrame(rootPart)

            if rootPart and targetRoot then
                print("🎤 " .. player.Name .. " is speaking! Following and flinging...")

                local followConn
                local startTime = tick()

                fling()

                local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")

                followConn = RunService.RenderStepped:Connect(function()
                    local elapsed = tick() - startTime
                    if elapsed > tpDuration or not toggle then
                        followConn:Disconnect()

                        if rootPart and originalCFrame then
                            unfling()
                            rootPart.Velocity = Vector3.zero
                            rootPart.RotVelocity = Vector3.zero
                            rootPart.CFrame = originalCFrame + Vector3.new(0, 1, 0)
                        else
                            warn("No valid originalCFrame to teleport back to")
                        end

                        task.wait(0.03)
                        unfling()
                        flungRecently = false
                        print("⌛ Done. Followed " .. player.Name .. " for " .. tpDuration .. "s")
                        return
                    end

                    if rootPart and targetRoot then
                        if humanoid and (
                            humanoid:GetState() == Enum.HumanoidStateType.Freefall or
                            humanoid:GetState() == Enum.HumanoidStateType.FallingDown or
                            humanoid:GetState() == Enum.HumanoidStateType.Physics
                        ) then
                            if originalCFrame then
                                rootPart.Velocity = Vector3.new(0,0,0)
                                rootPart.RotVelocity = Vector3.new(0,0,0)
                                rootPart.CFrame = originalCFrame + Vector3.new(0, 1, 0)
                            end
                        else
                            local offset = CFrame.new(0, 0, 0.5)
                            rootPart.CFrame = targetRoot.CFrame * offset
                        end
                    end
                end)

            else
                flungRecently = false
            end
        end
    end)

    connected[player] = {analyzer = analyzer, conn = conn}
    print("Listening to", player.Name)
end


local function startTracking()
    -- Track current players
    for _, player in ipairs(Players:GetPlayers()) do
        if targetName == "All" or player.Name == targetName then
            listenAndTeleport(player)
        end
    end

    -- Connect PlayerAdded
    local paConn = Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Wait()
        task.wait(1)
        if targetName == "All" or player.Name == targetName then
            listenAndTeleport(player)
        end
    end)
    table.insert(trackingConnections, paConn)

    -- Connect PlayerRemoving
    local prConn = Players.PlayerRemoving:Connect(function(player)
        local analyzer = connected[player]
        if analyzer then
            analyzer:Destroy()
        end
        connected[player] = nil
        print("Stopped listening to", player.Name)
    end)
    table.insert(trackingConnections, prConn)

    print("▶️ Started tracking players.")
end

local function stopTracking()
    for player, data in pairs(connected) do
        if data.conn then data.conn:Disconnect() end
        if data.analyzer then data.analyzer:Destroy() end
    end
    connected = {}

    for _, conn in pairs(trackingConnections) do
        conn:Disconnect()
    end
    trackingConnections = {}

    print("🛑 Stopped tracking all players.")
end

Players.PlayerRemoving:Connect(function(player)
    local data = connected[player]
    if data then
        if data.conn then data.conn:Disconnect() end
        if data.analyzer then data.analyzer:Destroy() end
    end
    connected[player] = nil
    print("Stopped listening to", player.Name)
end)

task.wait(1)
print("Checking if you can fling players...")

if canFlingPlayers() then
    print("You can fling other players!")
    print('Press "Z" to start the script!')
else
    print("You can't fling other players. Cancelling script...")
    print("TIP: Next time join a game with collision on for players.")
    return
end


UIS.InputBegan:Connect(function(input)
    if input.KeyCode == ToggleKey then
        toggle = not toggle

        if toggle then
            print("VC Flinger On!")
            startTracking()
        else
            print("VC Flinger Off!")
            stopTracking()
            unfling()
        end
    end
end)

