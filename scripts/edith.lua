local mod = _JUMPLIB_EXAMPLE_MOD

local storedData = {}

JumpLib:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function ()
    storedData = {}
end)

local EDITH_ID = Isaac.GetPlayerTypeByName("Edith (JumpLib)")

---@param entity Entity
---@return any
local getData = function (entity)
    local hash = GetPtrHash(entity)

    if not storedData[hash] then
        storedData[hash] = {}
    end

    return storedData[hash]
end

---@param tbl table
---@param element any
---@return boolean
local isIn = function (tbl, element)
    for _, v in pairs(tbl) do
        if v == element then
            return true
        end
    end
    return false
end

local directionToVector = {
    [Direction.NO_DIRECTION] = Vector.Zero,
    [Direction.LEFT] = Vector(-1, 0),
    [Direction.UP] = Vector(0, -1),
    [Direction.RIGHT] = Vector(1, 0),
    [Direction.DOWN] = Vector(0, 1),
}

---@param player EntityPlayer
---@param flag CacheFlag
mod:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE, CallbackPriority.LATE, function (_, player, flag)
    if player:GetPlayerType() ~= EDITH_ID then
        return
    end

    if flag == CacheFlag.CACHE_DAMAGE then
        player.Damage = player.Damage * 1.5
    elseif flag == CacheFlag.CACHE_TEARCOLOR then
        player.TearColor = Color(1.75, 2, 2)
    end
end)

---@param tear EntityTear
mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, function (_, tear)
    if tear.SpawnerType == EntityType.ENTITY_PLAYER
    and tear.SpawnerEntity:ToPlayer():GetPlayerType() == EDITH_ID then
        tear:ChangeVariant(TearVariant.ROCK)
        tear.Scale = tear.Scale * 0.88
    end
end)

---@param player EntityPlayer
mod:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, function (_, player)
    local data = getData(player)

    data.Cooldown = math.max(-1, (data.Cooldown or 100) - 1)
    data.DoubleTap = math.max(0, (data.DoubleTap or 15) - 1)

    if data.Cooldown == 0 then
        mod.SFX:Play(SoundEffect.SOUND_BEEP)
        player:SetColor(Color(1, 1, 1, 1, 1, 1, 1), 10, 99, true, false)
    end

    local dir = player:GetFireDirection()

    local isFiring = dir ~= Direction.NO_DIRECTION

    if isFiring then
        data.LastFireDirection = dir
    end

    if data.Cooldown <= 0 then
        if data.WasFiring == nil then
            data.WasFiring = isFiring
        end

        if not data.WasFiring and isFiring then
            data.DoubleTap = data.DoubleTap + 15
        end

        if data.DoubleTap > 15 then
            data.DoubleTap = 0
            data.Cooldown = 100
            data.LargeJump = true

            JumpLib:Jump(player, {
                Height = 12,
                Speed = 1.25,
                Flags = 0,
                ExtraData = {"JUMPLIB_EDITH_BIG_JUMP"},
            })
        end
    end

    data.WasFiring = isFiring

    if data.LargeJump then
        player.ControlsEnabled = false

        player:SetHeadDirection(data.LastFireDirection, 2, true)
        player.Velocity = player.Velocity * 0.5 + directionToVector[data.LastFireDirection]:Resized(3)
    end

    if player:GetMovementDirection() ~= Direction.NO_DIRECTION then
        JumpLib:TryJump(player, {
            Height = 6,
            Speed = 0.9,
            Flags = JumpLib.JumpFlags.WALK_PRESET | JumpLib.JumpFlags.IGNORE_PRE_JUMP | JumpLib.JumpFlags.IGNORE_PRE_SET_FALLSPEED,
            ExtraData = {"JUMPLIB_EDITH_HOP"}
        })
    end

    local jumpData = JumpLib:GetJumpData(player)

    if not jumpData.Jumping then
        player:SetCanShoot(true)
    else
        player:SetCanShoot(false)
    end
end, EDITH_ID)

---@param player EntityPlayer
---@param jumpData JumpData
---@param pitfall boolean
mod:AddCallback(JumpLib.Callbacks.POST_LAND, function (_, player, jumpData, pitfall)
    local data = getData(player)

    if isIn(jumpData.ExtraData, "JUMPLIB_EDITH_HOP") then
        mod.SFX:Play(SoundEffect.SOUND_STONE_IMPACT)
    end

    if isIn(jumpData.ExtraData, "JUMPLIB_EDITH_BIG_JUMP") then
        if not pitfall then
            mod.SFX:Play(SoundEffect.SOUND_STONE_IMPACT, 2, _, _, 0.8)
            mod.SFX:Play(SoundEffect.SOUND_FORESTBOSS_STOMPS, 0.5, _, _, 1.5)
            mod.Game:ShakeScreen(10)

            local effect = Isaac.Spawn(
                EntityType.ENTITY_EFFECT,
                EffectVariant.POOF01,
                0,
                player.Position,
                Vector.Zero,
                player
            ):ToEffect() ---@cast effect EntityEffect

            effect.Color = Color(1, 1.25, 1.25, 0.75, 0.25, 0.25, 0.25)

            player:SetMinDamageCooldown(30)

            for _, v in ipairs(Isaac.FindInRadius(player.Position, player.TearRange / 4, EntityPartition.ENEMY)) do
                v:TakeDamage(player.Damage * 5, DamageFlag.DAMAGE_CRUSH, EntityRef(player), 2)
            end

            player.ControlsEnabled = true
        end
        data.LargeJump = false
    end
end, {Player = EDITH_ID})