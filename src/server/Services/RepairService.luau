--!strict
-- Repairing a car parked in a bay: the owner holds the prompt, or the bay's mechanic works on it.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Strings = require(Shared.Config.Strings)
local Game = require(Shared.Config.Game)
local CarBuilder = require(Shared.CarBuilder)
local SoundFx = require(Shared.SoundFx)

local PlayerData = require(script.Parent.PlayerData)
local HireService = require(script.Parent.HireService)
local EmployeeService = require(script.Parent.EmployeeService)
local GamePassService = require(script.Parent.GamePassService)

-- Staff work speed: base by level × manager bonus × FastStaff pass.
local function staffSpeed(player: Player, level: number): number
	local speed = Game.MECHANIC_SPEED[level] or Game.MECHANIC_SPEED[1]
	local manager = HireService.managerLevel(player)
	if manager > 0 then
		speed *= 1 + (Game.MANAGER_SPEED[manager] or 0)
	end
	if GamePassService.owns(player, "FastStaff") then
		speed *= GamePassService.value("FastStaff")
	end
	return speed
end

local RepairService = {}

export type Job = {
	model: Model,
	player: Player,
	plotIndex: number,
	bayIndex: number,
	problemId: string,
	repairTime: number,
	onComplete: () -> (),
}

type ActiveJob = Job & {
	progress: number,
	prompt: ProximityPrompt,
	done: boolean,
	npc: Model?,
	lastAttr: number,
}

local active: { [Model]: ActiveJob } = {}

local function stopNpc(job: ActiveJob)
	if job.npc then
		pcall(EmployeeService.setWorking, job.npc, false)
		job.npc = nil
	end
end

local function finish(job: ActiveJob)
	if job.done then
		return
	end
	job.done = true
	active[job.model] = nil
	PlayerData.push(job.player)
	stopNpc(job)
	job.prompt:Destroy()
	job.model:SetAttribute("RepairProgress", 1)
	local root = job.model.PrimaryPart
	if root then
		Remotes.get("Effect"):FireClient(job.player, "Repair", root.Position + Vector3.new(0, 3, 0))
		SoundFx.play(root, "repairDone")
	end
	task.spawn(job.onComplete)
end

-- Starts a repair job. job.onComplete runs once when the car is fixed.
function RepairService.attach(job: Job)
	local root = job.model.PrimaryPart
	if not root then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = Strings.get("th", "prompt_repair")
	prompt.ObjectText = Strings.get("th", "problem_" .. job.problemId)
	prompt.HoldDuration = job.repairTime
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.UIOffset = Vector2.new(0, 40)
	prompt:SetAttribute("OwnerUserId", job.player.UserId)
	prompt:SetAttribute("ActionKey", "prompt_repair")
	prompt:SetAttribute("ObjectKey", "problem_" .. job.problemId)
	prompt.Parent = root

	local activeJob: ActiveJob = table.clone(job) :: any
	activeJob.progress = 0
	activeJob.prompt = prompt
	activeJob.done = false
	activeJob.npc = nil
	activeJob.lastAttr = 0
	active[job.model] = activeJob
	job.model:SetAttribute("RepairProgress", 0)
	PlayerData.push(job.player)

	prompt.Triggered:Connect(function(player)
		if player == job.player then
			finish(activeJob)
		end
	end)
end

-- Cancels a job without paying (plot released, car removed).
function RepairService.detach(model: Model)
	local job = active[model]
	if job then
		job.done = true
		active[model] = nil
		PlayerData.push(job.player)
		stopNpc(job)
		job.prompt:Destroy()
	end
end

-- Number of repairs in progress for a player.
function RepairService.activeCount(player: Player): number
	local count = 0
	for _, job in active do
		if job.player == player and not job.done then
			count += 1
		end
	end
	return count
end

-- Completes every active job of the player through the normal finish path (pay, stars, effects).
-- Returns how many were finished.
function RepairService.finishAll(player: Player): number
	local jobs: { ActiveJob } = {}
	for _, job in active do
		if job.player == player and not job.done then
			table.insert(jobs, job)
		end
	end
	for _, job in jobs do
		finish(job)
	end
	return #jobs
end

local function step(dt: number)
	for model, job in active do
		if job.done then
			continue
		end
		if not model.Parent then
			RepairService.detach(model)
			continue
		end
		local level = HireService.mechanicLevel(job.player, job.bayIndex)
		if level then
			if not job.npc then
				local npc = HireService.npcAt(job.plotIndex, "Bay" .. job.bayIndex)
				if npc then
					job.npc = npc
					-- The painter's mist takes the color of the car being worked on (nil = uniform color).
					pcall(EmployeeService.setWorking, npc, true, CarBuilder.bodyColor(model))
				end
			end
			job.progress += dt * staffSpeed(job.player, level) / job.repairTime
			if job.progress >= 1 then
				finish(job)
				continue
			end
			-- Attribute replication is throttled to ~10 Hz.
			if job.progress - job.lastAttr >= 0.05 then
				job.lastAttr = job.progress
				model:SetAttribute("RepairProgress", job.progress)
				job.prompt.HoldDuration = math.max(0.5, job.repairTime * (1 - job.progress))
			end
		elseif job.npc then
			stopNpc(job)
		end
	end
end

function RepairService.start()
	PlayerData.addSnapshotField(function(player, _data, snapshot)
		snapshot.repairsActive = RepairService.activeCount(player)
	end)
	RunService.Heartbeat:Connect(step)
end

return RepairService
