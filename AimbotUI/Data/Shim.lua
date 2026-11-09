--[[
  Aimbot UI - data shim for the bundled "What's Training?" spell data.

  The files in Data\ are taken UNCHANGED from the What's Training? addon by Sveng
  (MIT license, see LICENSE-WhatsTraining.txt) - the "Camelot" (Forever) class data.
  They expect a small table of helpers; this file provides them on our shared table.
]]
local ADDON_NAME, NS = ...

NS.ClassData = NS.ClassData or {}
function NS.forClass(token)
    NS.ClassData[token] = NS.ClassData[token] or {}
    return NS.ClassData[token]
end

-- the weapon skill file picks its master list from this; "forever" shares Era's masters
NS.gameVersion = "forever"
NS.locale = GetLocale and GetLocale() or "enUS"
