-- navet's general math lib
local ngl = {}

ngl.HitboxBoneIndex = { Head = 1, Neck = 2, Pelvis = 4, Body = 5, Chest = 7, Feet = 11 }
ngl.M_RADPI = 57.295779513082

ngl.SpecialWeaponIndexes = {
   [230] = "SYDNEY_SLEEPER",
   [61] = "AMBASSADOR",
   [1006] = "FESTIVE AMBASSADOR",
}

---@param angles EulerAngles
function ngl.AngleVectors(angles)
   return angles:Forward()
end

local function GetAimPosition(localplayer, weapon)
   local class = localplayer:GetPropInt("m_PlayerClass", "m_iClass")
   local item_def_idx = weapon:GetPropInt("m_Item", "m_iItemDefinitionIndex")

   if class == TF2_Sniper then
      if ngl.SpecialWeaponIndexes[item_def_idx] then return ngl.HitboxBoneIndex.Body end
      return localplayer:InCond(E_TFCOND.TFCond_Zoomed) and ngl.HitboxBoneIndex.Head or ngl.HitboxBoneIndex.Body
   elseif class == TF2_Spy then
      if ngl.SpecialWeaponIndexes[item_def_idx] then
         return weapon:GetWeaponSpread() > 0 and ngl.HitboxBoneIndex.Body or ngl.HitboxBoneIndex.Head
      end
   end

   return ngl.HitboxBoneIndex.Body
end

---@param source Vector3
---@param dest Vector3
---@return EulerAngles
function ngl.CalcAngle(source, dest)
   local angles = EulerAngles()
   local delta = source - dest

   angles.pitch = math.atan(delta.z / delta:Length2D()) * (180 / math.pi)
   angles.yaw = math.atan(delta.y, delta.x) * (180 / math.pi)

   if delta.x > 0 then
      angles.yaw = angles.yaw + 180
   elseif delta.x < 0 then
      angles.yaw = angles.yaw - 180
   end

   return angles
end

---@param src EulerAngles
---@param dst EulerAngles
---@return number
function ngl.CalcFov(src, dst)
   local v_source = src:Forward()
   local v_dest = dst:Forward()
   local result = math.deg(math.acos(v_dest:Dot(v_source) / v_dest:LengthSqr()))

   if result ~= result or result == math.huge then
      result = 0.0
   end

   return result
end

---@param number number
---@param min number
---@param max number
function ngl.Clamp(number, min, max)
   return math.max(min, math.min(max, number))
end

--- Gets the shooting position of the player with the view offset added
---@param player Entity
function ngl.GetShootPos(player)
   return (player:GetAbsOrigin() + player:GetPropVector("m_vecViewOffset[0]"))
end

function ngl.VisPos(entity, source, dest)
   local trace = engine.TraceLine(source, dest, (MASK_SHOT | CONTENTS_GRATE))
   if trace.entity then
      return (trace.entity == entity) or (trace.fraction > 0.99)
   else
      return false
   end
end

---@param entity Entity
---@param source Vector3
---@param dst Vector3
---@param hitbox integer
function ngl.VisPosHitboxId(entity, source, dst, hitbox)
   local trace = engine.TraceLine(source, dst, (MASK_SHOT | CONTENTS_GRATE))
   return (trace.entity and trace.entity == entity and trace.hitbox == hitbox)
end

---@param entity Entity
---@param src Vector3
---@param dst Vector3
function ngl.VisPosHitboxIdOut(entity, src, dst)
   local trace = engine.TraceLine(src, dst, (MASK_SHOT | CONTENTS_GRATE))
   if trace.entity and trace.entity == entity then
      return true
   end
   return false
end

---@param input Vector3
---@param matrix Matrix3x4
function ngl.VectorTransform(input, matrix)
   local output = Vector3()
   for i = 1, 3 do
      output[i] = input.x * matrix[i][1] + input.y * matrix[i][2] + input.z * matrix[i][3] + matrix[i][4]
   end
   return output
end

---Function to multipoint target's head \
---Returns respectively: \
---the position of the head, \
---the angle to it (so you can use usercmd.viewangles, for example) \
---and if it had to be multipointed or not
---@param target Entity
---@param localplayer Entity
function ngl.ScanHead(localplayer, target)
   local model = target:GetModel()
   local studioHdr = models.GetStudioModel(model)

   local pHitBoxSet = target:GetPropInt("m_nHitboxSet")
   local hitboxSet = studioHdr:GetHitboxSet(pHitBoxSet)
   local hitboxes = hitboxSet:GetHitboxes()

   local hitbox = hitboxes[ngl.HitboxBoneIndex.Head]
   local bone = hitbox:GetBone()
   local boneMatrices = target:SetupBones()
   local boneMatrix = boneMatrices[bone]
   local bonePos = Vector3(boneMatrix[1][4], boneMatrix[2][4], boneMatrix[3][4])

   local vMins, vMaxs = hitbox:GetBBMin(), hitbox:GetBBMax()

   local vLocalPos = ngl.GetShootPos(localplayer)

   local fScale = 0.8

   local vecPoints = {
      Vector3(((vMins.x + vMaxs.x) * 0.5), (vMins.y * fScale), ((vMins.z + vMaxs.z) * 0.5)),
      Vector3((vMins.x * fScale), ((vMins.y + vMaxs.y) * 0.5), ((vMins.z + vMaxs.z) * 0.5)),
      Vector3((vMaxs.x * fScale), ((vMins.y + vMaxs.y) * 0.5), ((vMins.z + vMaxs.z) * 0.5))
   }

   local vPos, vAngleTo, bHasMultiPointed

   bHasMultiPointed = false
   vPos = ngl.GetHitboxPos(target, ngl.HitboxBoneIndex.Head)
   vAngleTo = ngl.CalcAngle(vLocalPos, bonePos)

   for _, Point in ipairs(vecPoints) do
      local vTransformed = ngl.VectorTransform(Point, boneMatrix)
      if ngl.VisPosHitboxId(target, vLocalPos, vTransformed, ngl.HitboxBoneIndex.Head) then
         vPos = vTransformed
         vAngleTo = ngl.CalcAngle(vLocalPos, vTransformed)
         bHasMultiPointed = true
      end
   end
   return { pos = vPos, angle = vAngleTo, multipointed = bHasMultiPointed }
end

---Function to multipoint target's chest/body \
---Returns respectively: \
---the position of the head, \
---the angle to it (so you can use usercmd.viewangles, for example) \
---and if it had to be multipointed or not
---@param target Entity
---@param localplayer Entity
function ngl.ScanBody(localplayer, target)
   local model = target:GetModel()
   local studioHdr = models.GetStudioModel(model)

   local pHitBoxSet = target:GetPropInt("m_nHitboxSet")
   local hitboxSet = studioHdr:GetHitboxSet(pHitBoxSet)
   local hitboxes = hitboxSet:GetHitboxes()

   local hitbox = hitboxes[ngl.HitboxBoneIndex.Body]
   local bone = hitbox:GetBone()
   local boneMatrices = target:SetupBones()
   local boneMatrix = boneMatrices[bone]
   local bonePos = Vector3(boneMatrix[1][4], boneMatrix[2][4], boneMatrix[3][4])

   local vMins, vMaxs = hitbox:GetBBMin(), hitbox:GetBBMax()

   local vLocalPos = ngl.GetShootPos(localplayer)

   local fScale = 0.8

   local vecPoints = {
      Vector3(((vMins.x + vMaxs.x) * 0.5), (vMins.y * fScale), ((vMins.z + vMaxs.z) * 0.5)),
      Vector3((vMins.x * fScale), ((vMins.y + vMaxs.y) * 0.5), ((vMins.z + vMaxs.z) * 0.5)),
      Vector3((vMaxs.x * fScale), ((vMins.y + vMaxs.y) * 0.5), ((vMins.z + vMaxs.z) * 0.5))
   }

   local vPos, vAngleTo, bHasMultiPointed

   bHasMultiPointed = false
   vPos = ngl.GetHitboxPos(target, ngl.HitboxBoneIndex.Body)
   vAngleTo = ngl.CalcAngle(vLocalPos, bonePos)

   for _, Point in ipairs(vecPoints) do
      local vTransformed = ngl.VectorTransform(Point, boneMatrix)
      if ngl.VisPosHitboxId(target, vLocalPos, vTransformed, ngl.HitboxBoneIndex.Body) then
         vPos = vTransformed
         vAngleTo = ngl.CalcAngle(vLocalPos, vTransformed)
         bHasMultiPointed = true
      end
   end
   return { pos = vPos, angle = vAngleTo, multipointed = bHasMultiPointed }
end

---@param player Entity
function ngl.GetHitboxPos(player, hitbox)
   local model = player:GetModel()
   local studioHdr = models.GetStudioModel(model)

   local pHitBoxSet = player:GetPropInt("m_nHitboxSet")
   local hitboxSet = studioHdr:GetHitboxSet(pHitBoxSet)
   local hitboxes = hitboxSet:GetHitboxes()

   local hitbox = hitboxes[hitbox]
   local bone = hitbox:GetBone()

   local boneMatrices = player:SetupBones()
   local boneMatrix = boneMatrices[bone]
   if boneMatrix then
      local bonePos = Vector3(boneMatrix[1][4], boneMatrix[2][4], boneMatrix[3][4])
      return bonePos
   end
   return nil
end

---@param localplayer Entity
---@param target Entity
---@param hitbox integer
function ngl.ScanHitboxes(localplayer, target, hitbox)
   local vLocalPos = ngl.GetShootPos(localplayer)
   local targetPos = ngl.GetHitboxPos(target, hitbox)
   if not targetPos then return nil end
   if hitbox == ngl.HitboxBoneIndex.Body then
      return ngl.GetHitboxPos(target, hitbox),
          ngl.CalcAngle(vLocalPos, targetPos)
   end

   local vHitbox = ngl.GetHitboxPos(target, hitbox)

   if ngl.VisPos(target, vLocalPos, vHitbox) then
      local vAngleTo = ngl.CalculateAngle(vLocalPos, vHitbox)
      return vHitbox, vAngleTo
   end

   return nil
end

---@param localplayer Entity
---@param weapon Entity
---@param target Entity
function ngl.VerifyTarget(localplayer, weapon, target, hitbox)
   local targetPos = ngl.GetHitboxPos(target, hitbox)
   if not targetPos then return false end
   if hitbox == ngl.HitboxBoneIndex.Head then
      if (not ngl.VisPosHitboxIdOut(target, ngl.GetShootPos(localplayer), targetPos)) or (not ngl.ScanHead(localplayer, target)) then
         return false
      end
   elseif hitbox == ngl.HitboxBoneIndex.Body then
      if (not ngl.VisPos(target, ngl.GetShootPos(localplayer), targetPos)) or (not ngl.ScanHitboxes(localplayer, target, hitbox)) then
         return false
      end
   else
      if not ngl.VisPos(target, ngl.GetShootPos(localplayer), targetPos) then
         return false
      end
   end

   return true
end

---@param player Entity
---@return Entity
function ngl.GetCurrentWeapon(player)
   return player:GetPropEntity("m_hActiveWeapon")
end

---@param weapon Entity
function ngl.GetLastFireTime(weapon)
   return weapon:GetPropFloat("LocalActiveTFWeaponData", "m_flLastFireTime")
end

---@param weapon Entity
function ngl.GetNextPrimaryAttack(weapon)
   return weapon:GetPropFloat("LocalActiveWeaponData", "m_flNextPrimaryAttack")
end

function ngl.GetClip1(weapon)
   return weapon:GetPropInt("LocalWeaponData", "m_iClip1")
end

function ngl.GetPlayerAmmo(player)
   local ammoDataTable = player:GetPropDataTableInt("m_iAmmo")
   local weapon = ngl.GetCurrentWeapon(player)
   local clip1 = ngl.GetClip1(weapon)
   local primary_clip2, secondary_clip2 = ammoDataTable[2], ammoDataTable[3]
   return { currentweaponclip1 = clip1, primary_clip2 = primary_clip2, secondary_clip2 = secondary_clip2 }
end

function ngl.GetEngineerMetal(player)
   local ammoDataTable = player:GetPropDataTableInt("m_iAmmo")
   return ammoDataTable[4]
end

--- https://www.unknowncheats.me/forum/team-fortress-2-a/273821-canshoot-function.html
local lastFire = 0
local nextAttack = 0
local old_weapon = nil
---@param localplayer Entity
---@param weapon Entity
function ngl.CanWeaponShoot(localplayer, weapon)
   if not localplayer:IsAlive() then return false end
   local lastfiretime = ngl.GetLastFireTime(weapon)

   if lastFire ~= lastfiretime or weapon ~= old_weapon then
      lastFire = lastfiretime
      nextAttack = ngl.GetNextPrimaryAttack(weapon)
   end

   if weapon:GetPropInt("LocalWeaponData", "m_iClip1") == 0 then
      return false
   end

   old_weapon = weapon

   return nextAttack <= (localplayer:GetPropInt("m_nTickBase") * globals.TickInterval())
end

function ngl.clamp(number, min, max)
   number = (number < min and min or number)
   number = (number > max and max or number)
   return number
end

--- ~~pasted~~ borrowed from lnxlib
function ngl.RemapValClamped(val, A, B, C, D)
   if A == B then
      return val >= B and D or C
   end

   local cVal = (val - A) / (B - A)
   cVal = ngl.clamp(cVal, 0, 1)

   return C + (D - C) * cVal
end

--- ~~pasted~~ borrowed from lnxlib
-- Returns the projectile speed and gravity of the weapon
---@param weapon Entity
---@return table<number, number>?
function ngl.GetProjectileInfo(weapon)
   -- Projectile info by definition index
   local projInfo = {
      [414] = { 1540, 0 },     -- Liberty Launcher
      [308] = { 1513.3, 0.4 }, -- Loch n' Load
      [595] = { 3000, 0.2 },   -- Manmelter
   }

   -- Projectile info by weapon ID
   local projInfoID = {
      [E_WeaponBaseID.TF_WEAPON_ROCKETLAUNCHER] = { 1100, 0 },            -- Rocket Launcher
      [E_WeaponBaseID.TF_WEAPON_DIRECTHIT] = { 1980, 0 },                 -- Direct Hit
      [E_WeaponBaseID.TF_WEAPON_GRENADELAUNCHER] = { 1216.6, 0.5 },       -- Grenade Launcher
      [E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER] = { 1100, 0 },          -- Rocket Launcher
      [E_WeaponBaseID.TF_WEAPON_SYRINGEGUN_MEDIC] = { 1000, 0.2 },        -- Syringe Gun
      [E_WeaponBaseID.TF_WEAPON_FLAMETHROWER] = { 1000, 0.2, 0.33 },      -- Flame Thrower
      [E_WeaponBaseID.TF_WEAPON_FLAREGUN] = { 2000, 0.3 },                -- Flare Gun
      [E_WeaponBaseID.TF_WEAPON_CLEAVER] = { 3000, 0.2 },                 -- Flying Guillotine
      [E_WeaponBaseID.TF_WEAPON_CROSSBOW] = { 2400, 0.2 },                -- Crusader's Crossbow
      [E_WeaponBaseID.TF_WEAPON_SHOTGUN_BUILDING_RESCUE] = { 2400, 0.2 }, -- Rescue Ranger
      [E_WeaponBaseID.TF_WEAPON_CANNON] = { 1453.9, 0.4 },                -- Loose Cannon
   }
   local id = weapon:GetWeaponID()
   local defIndex = weapon:GetPropInt("m_iItemDefinitionIndex")

   -- Special cases
   if id == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW then
      local charge = globals.CurTime() - weapon:GetChargeBeginTime()
      return { ngl.RemapValClamped(charge, 0.0, 1.0, 1800, 2600),
         ngl.RemapValClamped(charge, 0.0, 1.0, 0.5, 0.1) }
   elseif id == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER then
      local charge = globals.CurTime() - weapon:GetChargeBeginTime()
      return { ngl.RemapValClamped(charge, 0.0, 4.0, 900, 2400),
         ngl.RemapValClamped(charge, 0.0, 4.0, 0.5, 0.0) }
   end

   return projInfo[defIndex] or projInfoID[id]
end

return ngl
