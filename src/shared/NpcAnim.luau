--!strict
-- NpcAnim: procedural walk / idle / work animation for NpcBuilder characters. It runs on every client
-- (NpcAnimator controller), because joint Transforms written on the server never reach the clients.
-- The server (NpcBuilder) only publishes what each character is doing as model Attributes; this module
-- turns those attributes into joint angles every frame.
--
-- Attributes on the model (all optional; missing = off):
--   AnimWalk 0/1, AnimSpeed (studs/s)         walk layer (its phase is integrated locally from the speed)
--   AnimIdle 0/1, AnimIdleT0                  idle layer; time = server time - T0, so every client agrees
--   AnimWork_<style> 0/1, AnimWorkT0_<style>  work layers: hammer | spray | reach (same clock as idle)
--   AnimWaveAt (server time), AnimWaveDur     right-hand wave of the idle layer
--   AnimCarry bool, AnimHold string, AnimStoop 0..1, AnimLean radians, AnimLook Vector3
--
-- Facing convention: a character's front is its root's -Z. Joint sign convention used by the poses
-- (Euler X on a hanging limb): positive swings it forward (-Z).

local NpcAnim = {}

NpcAnim.TAG = "NpcRig" -- CollectionService tag the server puts on every animated character
NpcAnim.WORK_STYLES = { "hammer", "spray", "reach" }
NpcAnim.HAMMER_RATE = 1.15 -- hammer swings per second (poseWork)
-- Phase (0..1) of the hammer swing at which the blow lands: the arm reaches the bottom of the downswing,
-- which starts at 0.65 (see poseWork), so sparks fly when the head actually meets the metal.
NpcAnim.HAMMER_STRIKE_PHASE = 0.96

export type Joint = Motor6D | AnimationConstraint
type Pose = { [string]: Vector3 }

-- Per-NPC quirks rolled once per client (multipliers around 1, so the average look is kept).
type Personality = {
	stride: number, -- walk swing size
	cadence: number, -- step frequency
	lookiness: number, -- how often the idle head looks around
}

type Layer = {
	kind: string, -- "walk" | "idle" | "work"
	style: string,
	targetAttr: string,
	t0Attr: string?,
	weight: number,
	time: number,
	rate: number, -- time units per second (walk: radians of gait phase)
	speed: number, -- walk speed in studs / second
	waveStart: number,
	waveUntil: number,
}

export type Rig = {
	model: Model,
	joints: { [string]: Joint },
	layers: { Layer },
	acc: Pose,
	asleep: boolean,
	personality: Personality,
	head: BasePart?,
	-- Look-at overlay on Neck / Waist (smoothed; lookW fades the overlay in and out).
	lookW: number,
	lookYaw: number,
	lookPitch: number,
	-- Held pose overlay on the arms (phone, hands in pockets). The pose stays until the fade finishes.
	hold: Pose?,
	holdTarget: number,
	holdW: number,
	-- Forward bend (e.g. setting a box down) and turning lean, both smoothed overlays.
	stoop: number,
	lean: number,
}

local V3 = Vector3.new
local CF = CFrame.new
local IDENTITY = CFrame.new()
local TWO_PI = math.pi * 2
local rng = Random.new()

local JOINT_NAMES = {
	"Root", "Waist", "Neck",
	"LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow",
	"LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle",
}
local JOINT_SET: { [string]: boolean } = {}
for _, name in JOINT_NAMES do
	JOINT_SET[name] = true
end
local POSE_KEYS: { string } = table.clone(JOINT_NAMES)
table.insert(POSE_KEYS, "RootPos")

local FADE_SECONDS = 0.22
-- Arms held forward around a carried box (overrides the arm joints of every layer).
local CARRY_POSE: { [string]: Vector3 } = {
	LeftShoulder = V3(1.15, 0, -0.12),
	RightShoulder = V3(1.15, 0, 0.12),
	LeftElbow = V3(0.45, 0, 0),
	RightElbow = V3(0.45, 0, 0),
}
-- Same idea as CARRY_POSE but fades in and out (AnimHold = "phone" | "pocket").
local HOLD_POSES: { [string]: Pose } = {
	phone = {
		RightShoulder = V3(1.05, 0, 0.18),
		RightElbow = V3(1.4, 0, 0),
	},
	pocket = {
		LeftShoulder = V3(-0.3, 0, -0.12),
		RightShoulder = V3(-0.3, 0, 0.12),
		LeftElbow = V3(0.55, 0, 0),
		RightElbow = V3(0.55, 0, 0),
	},
}
local LOOK_MAX_YAW = 1.0 -- head + waist turn limit toward a look-at target, radians
local LOOK_MAX_PITCH = 0.45
local CYCLE_LENGTH = 7 -- studs travelled per full gait cycle (two steps)
local DEFAULT_WALK_SPEED = 7
local HIP_AMP = 0.55
local KNEE_AMP = 0.95
local ARM_AMP = 0.5

local scratch: Pose = {}

local function num(model: Model, name: string, default: number): number
	local value = model:GetAttribute(name)
	if type(value) == "number" then
		return value
	end
	return default
end

local function collectJoints(model: Model): { [string]: Joint }
	local joints: { [string]: Joint } = {}
	for _, d in model:GetDescendants() do
		if JOINT_SET[d.Name] and joints[d.Name] == nil then
			if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
				joints[d.Name] = d
			end
		end
	end
	return joints
end

local function newLayer(kind: string, style: string, targetAttr: string, t0Attr: string?): Layer
	return {
		kind = kind,
		style = style,
		targetAttr = targetAttr,
		t0Attr = t0Attr,
		weight = 0,
		time = rng:NextNumber() * 10,
		rate = 1,
		speed = DEFAULT_WALK_SPEED,
		waveStart = -1,
		waveUntil = -1,
	}
end

function NpcAnim.newRig(model: Model): Rig
	local layers: { Layer } = {
		newLayer("walk", "", "AnimWalk", nil),
		newLayer("idle", "", "AnimIdle", "AnimIdleT0"),
	}
	for _, style in NpcAnim.WORK_STYLES do
		table.insert(layers, newLayer("work", style, "AnimWork_" .. style, "AnimWorkT0_" .. style))
	end
	local head = model:FindFirstChild("Head")
	return {
		model = model,
		joints = collectJoints(model),
		layers = layers,
		acc = {},
		asleep = false,
		-- Rolled once per NPC so a crowd does not move in lockstep (all centered on 1).
		personality = {
			stride = rng:NextNumber(0.85, 1.15),
			cadence = rng:NextNumber(0.9, 1.1),
			lookiness = rng:NextNumber(0.6, 1.4),
		},
		head = if head and head:IsA("BasePart") then head else nil,
		lookW = 0,
		lookYaw = 0,
		lookPitch = 0,
		hold = nil,
		holdTarget = 0,
		holdW = 0,
		stoop = 0,
		lean = 0,
	}
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function poseWalk(rig: Rig, layer: Layer, t: number, pose: Pose)
	local amp = math.clamp(layer.speed / 6, 0, 1.25) * rig.personality.stride
	local s, c = math.sin(t), math.cos(t)
	local hipL = HIP_AMP * amp * s
	local hipR = -hipL
	local kneeL = -(KNEE_AMP * amp * math.max(0, c) + 0.06 * amp)
	local kneeR = -(KNEE_AMP * amp * math.max(0, -c) + 0.06 * amp)
	pose.LeftHip = V3(hipL, 0, 0)
	pose.RightHip = V3(hipR, 0, 0)
	pose.LeftKnee = V3(kneeL, 0, 0)
	pose.RightKnee = V3(kneeR, 0, 0)
	pose.LeftAnkle = V3(-(hipL + kneeL) * 0.6, 0, 0)
	pose.RightAnkle = V3(-(hipR + kneeR) * 0.6, 0, 0)
	pose.LeftShoulder = V3(-ARM_AMP * amp * s, 0, -0.06)
	pose.RightShoulder = V3(ARM_AMP * amp * s, 0, 0.06)
	pose.LeftElbow = V3(0.2 + 0.45 * amp * math.max(0, -s), 0, 0)
	pose.RightElbow = V3(0.2 + 0.45 * amp * math.max(0, s), 0, 0)
	pose.Root = V3(0, -0.08 * amp * s, 0.03 * amp * s)
	pose.Waist = V3(-0.04 * amp, 0.16 * amp * s, -0.03 * amp * s)
	pose.Neck = V3(0.03 - 0.02 * amp * math.cos(2 * t), -0.08 * amp * s, 0)
	pose.RootPos = V3(0, amp * (0.07 * math.cos(2 * t) - 0.03), 0)
end

local function poseIdle(rig: Rig, layer: Layer, t: number, pose: Pose)
	local breath = math.sin(t * 2.1)
	local sway = math.sin(t * 0.9)
	pose.RootPos = V3(0, 0.02 * breath, 0)
	pose.Root = V3(0, 0.03 * math.sin(t * 0.5), 0.02 * sway)
	pose.Waist = V3(0.01 + 0.015 * breath, 0.04 * math.sin(t * 0.6 + 1), -0.02 * sway)
	local look = rig.personality.lookiness
	pose.Neck = V3(0.02 * math.sin(t * 0.8), 0.2 * (math.sin(t * 0.37 * look) + 0.5 * math.sin(t * 0.91 * look)), 0)
	local armSwing = 0.04 * math.sin(t * 1.3)
	pose.LeftShoulder = V3(armSwing, 0, -0.07 - 0.02 * breath)
	pose.LeftElbow = V3(0.12 + 0.02 * breath, 0, 0)
	local rightShoulder = V3(-armSwing, 0, 0.07 + 0.02 * breath)
	local rightElbow = V3(0.12 + 0.02 * breath, 0, 0)

	if layer.waveUntil > t and t >= layer.waveStart then
		local e = smooth(math.min((t - layer.waveStart) / 0.35, (layer.waveUntil - t) / 0.35))
		rightShoulder = rightShoulder:Lerp(V3(0.1, 0, 2.3), e)
		rightElbow = rightElbow:Lerp(V3(0, 0, 0.25 + 0.55 * math.sin((t - layer.waveStart) * 12)), e)
		pose.Neck = pose.Neck:Lerp(V3(0, 0, 0.06), e)
	end
	pose.RightShoulder = rightShoulder
	pose.RightElbow = rightElbow
end

local function poseWork(layer: Layer, t: number, pose: Pose)
	local style = layer.style
	if style == "spray" then
		local sweep = math.sin(t * 2.4)
		pose.RightShoulder = V3(1.45, 0, 0.4 * sweep)
		pose.RightElbow = V3(0.15, 0, 0)
		pose.LeftShoulder = V3(0.15, 0, -0.25)
		pose.LeftElbow = V3(0.95, 0, 0)
		pose.Waist = V3(-0.05, 0.14 * sweep, 0)
		pose.Neck = V3(-0.05, -0.1 * sweep, 0)
		pose.Root = V3(0, -0.04 * sweep, 0.02 * sweep)
		pose.RootPos = V3(0, 0.01 * math.sin(t * 2.1), 0)
	elseif style == "reach" then
		local k = math.sin(t * 2.2)
		pose.RightShoulder = V3(1.25 + 0.25 * k, 0, 0.12)
		pose.RightElbow = V3(0.55 + 0.25 * math.sin(t * 2.2 + 1), 0, 0)
		pose.LeftShoulder = V3(0.25, 0, -0.1)
		pose.LeftElbow = V3(0.6 + 0.1 * math.sin(t * 1.5), 0, 0)
		pose.Waist = V3(-0.06 + 0.02 * k, 0.1 * math.sin(t * 1.1), 0)
		pose.Neck = V3(-0.08, 0.35 * math.sin(t * 1.1), 0)
		pose.RootPos = V3(0, 0.01 * math.sin(t * 2.1), 0)
		pose.Root = V3(0, 0.03 * math.sin(t * 1.1), 0)
	else
		-- hammer: slow wind-up, fast strike, short pause
		local p = (t * NpcAnim.HAMMER_RATE) % 1
		local u: number
		if p < 0.65 then
			u = smooth(p / 0.65)
		else
			local q = (p - 0.65) / 0.35
			u = 1 - q * q
		end
		local down = 1 - u
		pose.RightShoulder = V3(0.5 + 1.2 * u, 0, 0.1)
		pose.RightElbow = V3(0.35 + 0.7 * u, 0, 0)
		pose.LeftShoulder = V3(0.6 + 0.1 * down, 0, -0.12)
		pose.LeftElbow = V3(0.9 + 0.1 * down, 0, 0)
		pose.Waist = V3(-(0.05 + 0.12 * down), 0.04 * math.sin(t * 0.7), 0)
		pose.Neck = V3(-0.1 + 0.05 * u, 0, 0)
		pose.RootPos = V3(0, -0.05 * down, 0)
		pose.LeftHip = V3(-0.12, 0, -0.05)
		pose.RightHip = V3(0.12, 0, 0.05)
		pose.LeftKnee = V3(-0.1, 0, 0)
		pose.RightKnee = V3(-0.1, 0, 0)
	end
end

local function writeIdentity(rig: Rig)
	for _, joint in rig.joints do
		joint.Transform = IDENTITY
	end
end

-- Advances one character by dt seconds and writes its joints. `now` is workspace:GetServerTimeNow().
function NpcAnim.update(rig: Rig, dt: number, now: number)
	local model = rig.model
	-- The engine upgrades the Motor6D joints of R15 models to AnimationConstraints (and replaces them), so
	-- joints cached early may be gone: look them up again. Nothing to do until the joints exist.
	local rootJoint = rig.joints.Root
	if rootJoint == nil or rootJoint.Parent == nil then
		rig.joints = collectJoints(model)
		if rig.joints.Root == nil then
			return
		end
	end

	local acc = rig.acc
	for _, key in POSE_KEYS do
		acc[key] = Vector3.zero
	end
	local sumWeight = 0
	local anyLive = false

	for _, layer in rig.layers do
		local weight = layer.weight
		local target = num(model, layer.targetAttr, 0)
		if weight ~= target then
			if weight < target then
				weight = math.min(target, weight + dt / FADE_SECONDS)
			else
				weight = math.max(target, weight - dt / FADE_SECONDS)
			end
			layer.weight = weight
		end
		if weight > 0 or target > 0 then
			anyLive = true
			if layer.kind == "walk" then
				layer.speed = math.max(0, num(model, "AnimSpeed", DEFAULT_WALK_SPEED))
				layer.rate = TWO_PI * layer.speed / CYCLE_LENGTH * rig.personality.cadence
				layer.time += dt * layer.rate
			else
				local t0Attr = layer.t0Attr
				local t0 = if t0Attr then model:GetAttribute(t0Attr) else nil
				if type(t0) == "number" then
					layer.time = now - t0
				else
					layer.time += dt
				end
				if layer.kind == "idle" then
					local waveAt = num(model, "AnimWaveAt", -1e9)
					layer.waveStart = layer.time - (now - waveAt)
					layer.waveUntil = layer.waveStart + num(model, "AnimWaveDur", 0)
				end
			end
			if weight > 0 then
				for _, key in POSE_KEYS do
					scratch[key] = Vector3.zero
				end
				if layer.kind == "walk" then
					poseWalk(rig, layer, layer.time, scratch)
				elseif layer.kind == "idle" then
					poseIdle(rig, layer, layer.time, scratch)
				else
					poseWork(layer, layer.time, scratch)
				end
				sumWeight += weight
				for _, key in POSE_KEYS do
					acc[key] += scratch[key] * weight
				end
			end
		end
	end

	-- Look-at overlay: aim the head at a world point in front of the character, fade out otherwise.
	local wantLook = 0
	local lookTarget = model:GetAttribute("AnimLook")
	local root = model.PrimaryPart
	if typeof(lookTarget) == "Vector3" and root then
		local rel = root.CFrame:PointToObjectSpace(lookTarget)
		if rel.Z < -0.3 then -- the front is -Z; targets beside or behind us are ignored
			local head = rig.head
			local headHeight = if head then head.Position.Y - root.Position.Y else 1.8
			local horizontal = math.max(math.sqrt(rel.X * rel.X + rel.Z * rel.Z), 0.5)
			local goalYaw = math.clamp(math.atan2(-rel.X, -rel.Z), -LOOK_MAX_YAW, LOOK_MAX_YAW)
			local goalPitch = math.clamp(math.atan2(rel.Y - headHeight, horizontal), -LOOK_MAX_PITCH, LOOK_MAX_PITCH)
			local follow = 1 - math.exp(-7 * dt)
			rig.lookYaw += (goalYaw - rig.lookYaw) * follow
			rig.lookPitch += (goalPitch - rig.lookPitch) * follow
			wantLook = 1
		end
	end
	rig.lookW += (wantLook - rig.lookW) * (1 - math.exp(-5 * dt))
	if wantLook == 0 and rig.lookW < 0.002 then
		rig.lookW = 0
	end

	-- Held pose (phone / pockets), forward bend and turn lean fade toward their targets.
	local holdKind = model:GetAttribute("AnimHold")
	local holdPose = if type(holdKind) == "string" then HOLD_POSES[holdKind] else nil
	if holdPose then
		rig.hold = holdPose
		rig.holdTarget = 1
	else
		rig.holdTarget = 0 -- the pose reference is dropped once the fade-out finishes
	end
	rig.holdW += (rig.holdTarget - rig.holdW) * (1 - math.exp(-9 * dt))
	if rig.holdTarget == 0 and rig.holdW < 0.01 then
		rig.holdW = 0
		rig.hold = nil
	end
	local stoopTarget = math.clamp(num(model, "AnimStoop", 0), 0, 1)
	local leanTarget = num(model, "AnimLean", 0)
	local smoothing = 1 - math.exp(-8 * dt)
	rig.stoop += (stoopTarget - rig.stoop) * smoothing
	if stoopTarget == 0 and rig.stoop < 0.002 then
		rig.stoop = 0
	end
	rig.lean += (leanTarget - rig.lean) * smoothing
	if leanTarget == 0 and math.abs(rig.lean) < 0.002 then
		rig.lean = 0
	end

	local carry = model:GetAttribute("AnimCarry") == true
	local overlayBusy = carry
		or rig.hold ~= nil
		or typeof(lookTarget) == "Vector3"
		or rig.lookW > 0
		or rig.stoop > 0
		or stoopTarget > 0
		or rig.lean ~= 0
		or leanTarget ~= 0
	if not anyLive and not overlayBusy then
		if not rig.asleep then
			writeIdentity(rig)
			rig.asleep = true
		end
		return
	end
	rig.asleep = false

	local norm = if sumWeight > 1 then 1 / sumWeight else 1
	local heldPose: Pose? = if carry then CARRY_POSE else rig.hold
	local heldWeight = if carry then 1 else rig.holdW
	local lookW = rig.lookW
	local stoop = rig.stoop
	for name, joint in rig.joints do
		local v = acc[name] * norm
		local held = if heldPose then heldPose[name] else nil
		if held then
			v = v:Lerp(held, heldWeight)
		end
		if name == "Root" then
			joint.Transform = CF(acc.RootPos * norm + V3(0, -0.14 * stoop, 0)) * CFrame.Angles(v.X, v.Y, v.Z + rig.lean)
		else
			if name == "Neck" then
				if lookW > 0 then
					v = v:Lerp(V3(rig.lookPitch, rig.lookYaw * 0.75, 0), lookW)
				end
				v += V3(0.18 * stoop, 0, 0)
			elseif name == "Waist" then
				-- Head yaw is split between the neck (75%) and the waist (25%) so the total stays within the limit.
				v += V3(-0.45 * stoop, rig.lookYaw * 0.25 * lookW, 0)
			elseif name == "LeftHip" or name == "RightHip" then
				v += V3(0.3 * stoop, 0, 0)
			elseif name == "LeftKnee" or name == "RightKnee" then
				v += V3(-0.5 * stoop, 0, 0)
			elseif name == "LeftAnkle" or name == "RightAnkle" then
				v += V3(0.2 * stoop, 0, 0)
			end
			joint.Transform = CFrame.Angles(v.X, v.Y, v.Z)
		end
	end
end

return NpcAnim
