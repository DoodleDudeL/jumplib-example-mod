---@class JumpConfig
---@field Height number
---@field Speed number | nil
---@field Flags integer | nil
---@field ExtraData string[] | nil

---@class JumpData
---@field Jumping boolean
---@field StartHeight number
---@field Height number
---@field StartSpeed number
---@field Speed number
---@field Flags integer
---@field ExtraData string[]

local game = Game()

JumpLib = RegisterMod("JumpLib", 1)

JumpLib.Constants = {
    PITFALL_DELAY_1 = 15,
    PITFALL_DELAY_2 = 20,
    PITFALL_DELAY_3 = 40,
}

---@enum JumpCallbacks
JumpLib.Callbacks =  {
    PRE_JUMP = "MC_JUMPLIB_PRE_JUMP",
    POST_JUMP = "MC_JUMPLIB_POST_JUMP",
    PRE_LAND = "MC_JUMPLIB_PRE_LAND",
    POST_LAND = "MC_JUMPLIB_POST_LAND",
    PRE_PITFALL = "MC_JUMPLIB_PRE_PITFALL",
    PRE_PITFALL_DAMAGE = "MC_JUMPLIB_PRE_PITFALL_DAMAGE",
    PRE_SET_FALLSPEED = "MC_JUMPLIB_PRE_SET_FALLSPEED",
    POST_SET_FALLSPEED = "MC_JUMPLIB_POST_SET_FALLSPEED",
    POST_UPDATE = "MC_JUMPLIB_POST_UPDATE",
    POST_UPDATE_60 = "MC_JUMPLIB_POST_UPDATE_60",
}

---@enum JumpFlags
JumpLib.JumpFlags = {
    NO_PITFALL = 1 << 0,
    NO_DAMAGE_PITFALL = 1 << 1,
    IGNORE_FLIGHT = 1 << 2,
    COLLISION_GRID = 1 << 3,
    COLLISION_ENTITY = 1 << 4,
    OVERWRITABLE = 1 << 5,
    KNIFE_COLLISION = 1 << 6,
    KNIFE_STAY_GROUNDED = 1 << 7,
    IGNORE_PRE_SET_FALLSPEED = 1 << 8,
    IGNORE_PRE_JUMP = 1 << 9,
    IGNORE_SET_FALLSPEED = 1 << 10,
}

JumpLib.JumpFlags.WALK_PRESET =
    JumpLib.JumpFlags.COLLISION_GRID
    | JumpLib.JumpFlags.COLLISION_ENTITY
    | JumpLib.JumpFlags.KNIFE_COLLISION

local storedData = {}

JumpLib:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function ()
    storedData = {}
end)

---@param entity Entity
---@return any
local getData = function (entity)
    local hash = GetPtrHash(entity)

    if not storedData[hash] then
        storedData[hash] = {}
    end

    return storedData[hash]
end

---@param entity Entity
---@return EntityPlayer?
local getPlayer = function (entity) -- Stolen from TSIL! Go check out Library of Isaac <3
    if entity.Parent then
        local player = entity.Parent:ToPlayer()

        if player then
            return player
        end

        local familiar = entity.Parent:ToFamiliar()

        if familiar then
            return familiar.Player
        end
    end

    if entity.SpawnerEntity then
        local player = entity.SpawnerEntity:ToPlayer()

        if player then
            return player
        end

        local familiar = entity.SpawnerEntity:ToFamiliar()

        if familiar then
            return familiar.Player
        end
    end

    return entity:ToPlayer()
end

---@param callback JumpCallbacks
---@param player EntityPlayer
---@param ... any
---@return any[]
local runCallback = function (callback, player, ...)
    local callbacks = {}

    for i, v in pairs(Isaac.GetCallbacks(callback)) do
        local param = v.Param

        local isPlayer = true
        local hasCollectible = true
        local hasTrinket = true

        if type(param) == "table" then
            if param.Player then
                if player:GetPlayerType() ~= param.Player then
                    isPlayer = false
                end
            end
            if param.Collectible then
                if not player:HasCollectible(param.Collectible) then
                    hasCollectible = false
                end
            end
            if param.Trinket then
                if not player:HasTrinket(param.Trinket) then
                    hasTrinket = false
                end
            end
        end

        if isPlayer and hasCollectible and hasTrinket then
            callbacks[i] = v.Function(nil, player, ...)
        end
    end

    return callbacks
end

---@param player EntityPlayer
---@return JumpData
function JumpLib:GetJumpData(player)
    local data = getData(player)

    return {
        Jumping = data.IsJumping,
        StartHeight = data.StartHeight or 0,
        Height = data.Height or 0,
        StartSpeed = data.Start or 0,
        CurrentSpeed = data.Decr or 0,
        Flags = data.Flags or 0,
        ExtraData = data.ExtraData or {},
    }
end

---@param player EntityPlayer
---@return boolean
function JumpLib:CanJump(player)
    local jumpData = JumpLib:GetJumpData(player)

    if (jumpData.Flags or 0) & JumpLib.JumpFlags.OVERWRITABLE ~= 0 then
        return true
    end

    return not jumpData.Jumping
end

---@param player EntityPlayer
---@param config JumpConfig
function JumpLib:Jump(player, config)
    config = {
        Height = config.Height,
        Speed = config.Speed or 1,
        Flags = config.Flags or 0,
        ExtraData = config.ExtraData or {},
    }

    for _, v in pairs(runCallback(JumpLib.Callbacks.PRE_JUMP, player, config)) do
        local newConfig = v

        local returnType = type(newConfig)

        if returnType == "table" and config.Flags & JumpLib.JumpFlags.IGNORE_PRE_JUMP ~= 0 then
            config = newConfig
        elseif returnType and returnType == "boolean" then
            return
        end
    end

    local data = getData(player)

    data.Height = data.Height or 0

    data.Start = (config.Height  * 2) * (config.Speed * 0.2)

    data.Speed = config.Speed

    data.ExtraData = config.ExtraData

    data.Flags = config.Flags

    data.Decr = 0

    if not data.StoredEntityColl and data.Flags & JumpLib.JumpFlags.COLLISION_ENTITY == 0 then
        data.StoredEntityColl = player.EntityCollisionClass
        player.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    end

    if not data.StoredGridColl and data.Flags & JumpLib.JumpFlags.COLLISION_GRID == 0 then
        data.StoredGridColl = player.GridCollisionClass
        player.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_WALLS
    end

    data.IsJumping = true

    runCallback(JumpLib.Callbacks.POST_JUMP, player, JumpLib:GetJumpData(player))
end

---@param player EntityPlayer
---@param config JumpConfig
---@return boolean
function JumpLib:TryJump(player, config)
    local canJump = JumpLib:CanJump(player)

    if canJump then
        JumpLib:Jump(player, config)
    end

    return canJump
end

---@param player EntityPlayer
---@param speed number
---@return boolean
function JumpLib:SetFallspeed(player, speed)
    local jumpData = JumpLib:GetJumpData(player)

    if jumpData.Jumping and jumpData.Flags & JumpLib.JumpFlags.IGNORE_SET_FALLSPEED == 0 then
        for _, v in pairs(runCallback(JumpLib.Callbacks.PRE_SET_FALLSPEED, player, speed, jumpData)) do
            if v == true then
                return false
            elseif type(v) == "number"
            and jumpData.Flags & JumpLib.JumpFlags.IGNORE_PRE_SET_FALLSPEED == 0 then
                speed = speed * v
            end
        end

        local data = getData(player)

        data.Speed = speed

        runCallback(JumpLib.Callbacks.POST_SET_FALLSPEED, player, speed, jumpData)

        return true
    end

    return false
end

---@param player EntityPlayer
function JumpLib:CancelJump(player)
    local data = getData(player)
    local jumpData = JumpLib:GetJumpData(player)

    data.IsJumping = false

    if jumpData.Flags & JumpLib.JumpFlags.COLLISION_ENTITY == 0 then
        player.EntityCollisionClass = data.StoredEntityColl or EntityCollisionClass.ENTCOLL_ALL
    end

    if jumpData.Flags & JumpLib.JumpFlags.COLLISION_GRID == 0 then
        player.GridCollisionClass = data.StoredGridColl
        player:AddCacheFlags(CacheFlag.CACHE_FLYING, true)
    end

    data.Flags = 0

    data.Decr = nil

    data.StoredEntityColl = nil
    data.StoredGridColl = nil
end

---@param player EntityPlayer
---@return Vector
function JumpLib:GetRenderOffset(player)
    local offset = Vector(0, -JumpLib:GetJumpData(player).Height)

    if game:GetRoom():GetRenderMode() == RenderMode.RENDER_WATER_REFLECT then
        offset = -offset
    end

    return offset
end

---@param player EntityPlayer
---@param position Vector
---@param hurt boolean | nil
function JumpLib:Pitfall(player, position, hurt)
    if hurt == nil then
        hurt = true
    end

    player:PlayExtraAnimation("FallIn")

    local data = getData(player)
    local jumpData = JumpLib:GetJumpData(player)

    data.Pitfall = true
    data.PitPos = position

    data.StoredEntityColl = player.EntityCollisionClass
    data.StoredGridColl = player.GridCollisionClass

    Isaac.CreateTimer(function ()
        for _, v in pairs(runCallback(JumpLib.Callbacks.PRE_PITFALL_DAMAGE, player, jumpData)) do
            if v == true then
                hurt = false
            end
        end

        if hurt then
            player:TakeDamage(1, DamageFlag.DAMAGE_PITFALL, EntityRef(player), 30)
        end
    end, JumpLib.Constants.PITFALL_DELAY_1, 1, true)

    Isaac.CreateTimer(function ()
        player:AnimatePitfallOut()

        player.SpriteScale = data.StoredSpriteScale

        data.StoredSpriteScale = nil

        data.PitPos = game:GetRoom():FindFreePickupSpawnPosition(player.Position, 40)
    end, JumpLib.Constants.PITFALL_DELAY_2, 0, true)

    Isaac.CreateTimer(function ()
        data.Pitfall = false
        PitPos = nil

        player.ControlsEnabled = true

        player.GridCollisionClass = data.StoredGridColl
        player.EntityCollisionClass = data.StoredEntityColl

        data.StoredGridColl = nil
        data.StoredEntityColl = nil
    end, JumpLib.Constants.PITFALL_DELAY_3, 0, true)
end

---@param player EntityPlayer
---@return boolean
function JumpLib:IsPitfalling(player)
    return not not getData(player).Pitfall
end

---@param player EntityPlayer
local jumpMain = function (_, player)
    local jumpData = JumpLib:GetJumpData(player)

    if not jumpData.Jumping then
        return
    end

    local data = getData(player)

    local gridColl = jumpData.Flags & JumpLib.JumpFlags.COLLISION_GRID == 0

    if gridColl then
        player.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_WALLS
    end

    if jumpData.Flags & JumpLib.JumpFlags.COLLISION_ENTITY == 0 then
        player.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    end

    data.Decr = data.Decr + 0.2 * data.Speed

    data.Height = math.max(
        data.Height + data.Start - data.Decr * data.Speed,
        0
    )

    if data.Height <= 0 then
        runCallback(JumpLib.Callbacks.PRE_LAND, player, jumpData)

        JumpLib:CancelJump(player)

        local pitFound = false

        if jumpData.Flags & JumpLib.JumpFlags.NO_PITFALL == 0 then
            if gridColl then
                local room = game:GetRoom()

                local canFly = player.CanFly
                local hurt = jumpData.Flags & JumpLib.JumpFlags.NO_DAMAGE_PITFALL == 0

                if jumpData.Flags & JumpLib.JumpFlags.IGNORE_FLIGHT ~= 0 then
                    canFly = false
                end

                if not (canFly or room:HasLava()) then
                    local fall = true

                    for _, v in pairs(runCallback(JumpLib.Callbacks.PRE_PITFALL, player, jumpData)) do
                        if v == true then
                            fall = false
                            break
                        elseif v == false then
                            hurt = false
                        end
                    end

                    if fall then
                        local grid = room:GetGridEntityFromPos(player.Position)
                        local pit

                        if grid then
                            pit = grid:ToPit()
                        end

                        if pit and pit.State == 0 then
                            pitFound = true
                            JumpLib:Pitfall(player, grid.Position, hurt)
                        end
                    end
                end
            end
        end
        runCallback(JumpLib.Callbacks.POST_LAND, player, jumpData, pitFound)
    end

    runCallback(JumpLib.Callbacks.POST_UPDATE_60, player, jumpData)
end
JumpLib:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, jumpMain)

---@param player EntityPlayer
local playerOffset = function (_, player)
    if JumpLib:GetJumpData(player).Jumping then
        return JumpLib:GetRenderOffset(player)
    end
end
JumpLib:AddCallback(ModCallbacks.MC_PRE_PLAYER_RENDER, playerOffset)

---@param player EntityPlayer
local pEffectUpdate = function (_, player)
    local data = getData(player)
    local jumpData = JumpLib:GetJumpData(player)

    if jumpData.Jumping then
        runCallback(JumpLib.Callbacks.POST_UPDATE, player, jumpData)
    end

    if not data.Pitfall then
        return
    end

    player.ControlsEnabled = false

    player.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    player.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE

    player.Velocity = (data.PitPos - player.Position) * 0.1

    if player:GetSprite():IsFinished("FallIn") and player.SpriteScale ~= Vector.Zero then
        data.StoredSpriteScale = player.SpriteScale
        player.SpriteScale = Vector.Zero
    end
end
JumpLib:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, pEffectUpdate)

---@param player EntityPlayer
local cancelJump = function (_, player)
    if getData(player).Pitfall then
        return true
    end
end
JumpLib:AddCallback(JumpLib.Callbacks.PRE_JUMP, cancelJump)

---@param knife EntityKnife
local knifeRender = function (_, knife)
    local player = getPlayer(knife)

    if not player then
        return
    end

    local data = getData(knife)
    local jumpData = JumpLib:GetJumpData(player)

    data.StoredEntityColl = data.StoredEntityColl or knife.EntityCollisionClass

    if jumpData.Flags & JumpLib.JumpFlags.KNIFE_COLLISION ~= 0
    or not jumpData.Jumping then
        knife.EntityCollisionClass = data.StoredEntityColl
        data.StoredEntityColl = nil
    else
        knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    end

    if jumpData.Flags & JumpLib.JumpFlags.KNIFE_STAY_GROUNDED == 0 then
        return JumpLib:GetRenderOffset(player)
    end
end
JumpLib:AddCallback(ModCallbacks.MC_PRE_KNIFE_RENDER, knifeRender)