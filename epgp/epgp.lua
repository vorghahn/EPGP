-- This is the core addon. It implements all functions dealing with
-- administering and configuring EPGP. It implements the following
-- functions:
--
-- StandingsSort(order): Sorts the standings list using the specified
-- sort order. Valid values are: NAME, EP, GP, PR. If order is nil it
-- returns the current value.
--
-- StandingsShowEveryone(val): Sets listing everyone or not in the
-- standings when in raid. If val is nil it returns the current
-- value.
--
-- GetNumMembers(): Returns the number of members in the standings.
--
-- GetMember(i): Returns the ith member in the standings based on the
-- current sort.
--
-- GetMain(name): Returns the main character for this member.
--
-- GetNumAlts(name): Returns the number of alts for this member.
--
-- GetAlt(name, i): Returns the ith alt for this member.
--
-- SelectMember(name): Select the member for award. Returns true if
-- the member was added, false otherwise.
--
-- DeSelectMember(name): Deselect member for award. Returns true if
-- the member was added, false otherwise.
--
-- GetNumMembersInAwardList(): Returns the number of members in the
-- award list.
--
-- IsMemberInAwardList(name): Returns true if member is in the award
-- list. When in a raid, this returns true for members in the raid and
-- members selected. When not in raid this returns true for everyone
-- if noone is selected or true if at least one member is selected and
-- the member is selected as well.
--
-- IsMemberInExtrasList(name): Returns true if member is in the award
-- list as an extra. When in a raid, this returns true if the member
-- is not in raid but is selected. When not in raid, this returns
-- false.
--
-- IsAnyMemberInExtrasList(name): Returns true if there is any member
-- in the award list as an extra.
--
-- ResetEPGP(): Resets all EP and GP to 0.
--
-- DecayEPGP(): Decays all EP and GP by the configured decay percent
-- (GetDecayPercent()).
--
-- CanIncEPBy(reason, amount): Return true reason and amount are
-- reasonable values for IncEPBy and the caller can change EPGP.
--
-- IncEPBy(name, reason, amount): Increases the EP of member <name> by
-- <amount>. Returns the member's main character name.
--
-- CanIncGPBy(reason, amount): Return true if reason and amount are
-- reasonable values for IncGPBy and the caller can change EPGP.
--
-- IncGPBy(name, reason, amount): Increases the GP of member <name> by
-- <amount>. Returns the member's main character name.
--
-- IncMassEPBy(reason, amount): Increases the EP of all members
-- in the award list. See description of IsMemberInAwardList.
--
-- RecurringEP(val): Sets recurring EP to true/false. If val is nil it
-- returns the current value.
--
-- RecurringEPPeriodMinutes(val): Sets the recurring EP period in
-- minutes. If val is nil it returns the current value.
--
-- GetDecayPercent(): Returns the decay percent configured in guild info.
--
-- CanDecayEPGP(): Returns true if the caller can decay EPGP.
--
-- GetBaseGP(): Returns the base GP configured in guild info.
--
-- GetMinEP(): Returns the min EP configured in guild info.
--
-- GetEPGP(name): Returns <ep, gp, main> for <name>. <main> will be
-- nil if this is the main toon, otherwise it will be the name of the
-- main toon since this is an alt. If <name> is an invalid name it
-- returns nil.
--
-- GetClass(name): Returns the class of member <name>. It returns nil
-- if the class is unknown.
--
-- ReportErrors(outputFunc): Calls function for each error during
-- initialization, one line at a time.
--
-- The library also fires the following messages, which you can
-- register for through RegisterCallback and unregister through
-- UnregisterCallback. You can also unregister all messages through
-- UnregisterAllCallbacks.
--
-- StandingsChanged: Fired when the standings have changed.
--
-- EPAward(name, reason, amount, mass): Fired when an EP award is
-- made.  mass is set to true if this is a mass award or decay.
--
-- MassEPAward(names, reason, amount,
--             extras_names, extras_reason, extras_amount): Fired
-- when a mass EP award is made.
--
-- GPAward(name, reason, amount, mass): Fired when a GP award is
-- made. mass is set to true if this is a mass award or decay.
--
-- BankedItem(name, reason, amount, mass): Fired when an item is
-- disenchanted or deposited directly to the Guild Bank. Name is
-- always the content of GUILD_BANK, amount is 0 and mass always nil.
--
-- StartRecurringAward(reason, amount, mins): Fired when recurring
-- awards are started.
--
-- StopRecurringAward(): Fired when recurring awards are stopped.
--
-- RecurringAwardUpdate(reason, amount, remainingSecs): Fired
-- periodically between awards with the remaining seconds to award in
-- seconds.
--
-- EPGPReset(): Fired when EPGP are reset.
--
-- Decay(percent): Fired when a decay happens.
--
-- DecayPercentChanged(v): Fired when decay percent changes. v is the
-- new value.
--
-- BaseGPChanged(v): Fired when base gp changes. v is the new value.
--
-- MinEPChanged(v): Fired when min ep changes. v is the new value.
--
-- ExtrasPercentChanged(v): Fired when extras percent changes.  v is
-- the new value.
--

local Debug = LibStub("LibDebug-1.0")
Debug:EnableDebugging()
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")
local GS = LibStub("LibGuildStorage-1.0")

EPGP = LibStub("AceAddon-3.0"):NewAddon(
  "EPGP", "AceEvent-3.0", "AceConsole-3.0")
local EPGP = EPGP
EPGP:SetDefaultModuleState(false)
local modulePrototype = {
  IsDisabled = function (self, i) return not self:IsEnabled() end,
  SetEnabled = function (self, i, v)
                 if v then
                   Debug("Enabling module: %s", self:GetName())
                   self:Enable()
                 else
                   Debug("Disabling module: %s", self:GetName())
                   self:Disable()
                 end
                 self.db.profile.enabled = v
               end,
  GetDBVar = function (self, i) return self.db.profile[i[#i]] end,
  SetDBVar = function (self, i, v) self.db.profile[i[#i]] = v end,
}
EPGP:SetDefaultModulePrototype(modulePrototype)

local version = GetAddOnMetadata('EPGP', 'Version')
if not version or #version == 0 then
  version = "(development)"
end
EPGP.version = version

local CallbackHandler = LibStub("CallbackHandler-1.0")
if not EPGP.callbacks then
  EPGP.callbacks = CallbackHandler:New(EPGP)
end
local callbacks = EPGP.callbacks

local global_config = {}
local ep_data = {}
local gp_data = {}
local main_data = {}
local alt_data = {}
local ignored = {}
local db
local standings = {}
local selected = {}
local oog_alts = {}
local oog_main_alt_list = {}
selected._count = 0  -- This is safe since _ is not allowed in names

local decode_class = {
["dh"]="DEMONHUNTER",
["dk"]="DEATHKNIGHT",
["de"]="DEATHKNIGHT",
["DEATHKNIGHT"]="DEATHKNIGHT",
["dr"]="DRUID",
["du"]="DRUID",
["DRUID"]="DRUID",
["h"]="HUNTER",
["hu"]="HUNTER",
["HUNTER"]="HUNTER",
["m"]="MAGE",
["ma"]="MAGE",
["MAGE"]="MAGE",
["pa"]="PALADIN",
["PALADIN"]="PALADIN",
["pr"]="PRIEST",
["PRIEST"]="PRIEST",
["r"]="ROGUE",
["ROGUE"]="ROGUE",
["ro"]="ROGUE",
["s"]="SHAMAN",
["sh"]="SHAMAN",
["SHAMAN"]="SHAMAN",
["lo"]="WARLOCK",
["WARLOCK"]="WARLOCK",
["wa"]="WARRIOR",
["wa"]="WARRIOR",
["WARRIOR"]="WARRIOR"
}

local encode_class = {
["DEMONHUNTER"]="dh",
["DEATHKNIGHT"]="de",
["DRUID"]="dr",
["HUNTER"]="h",
["MAGE"]="m",
["PALADIN"]="pa",
["PRIEST"]="pr",
["ROGUE"]="r",
["SHAMAN"]="s",
["WARLOCK"]="lo",
["WARRIOR"]="wa",
}

local function DecodeNote(note)
  if note then
    if note == "" then
      return 0, 0, 0
    else
	  if string.find(note, ";") then
	    local alt = string.match(note, ";(%w+)/")
		local ep, gp = string.match(note, "^(%d+),(%d+);")
		if ep then 
		  return tonumber(ep), tonumber(gp), alt
		end
	  else
	    local ep, gp = string.match(note, "^(%d+),(%d+)$")
		return tonumber(ep), tonumber(gp), 0
	  end
    end
  end
end

local function ScrapeClass(note)
  if note then
    if note == "" then
      return "DEATHKNIGHT"
    else
	  if string.find(note, "/") then
	    local class = string.lower(string.match(note, "/(%w+)"))
		local class_decoded = decode_class[class]
		if class_decoded then 
		  return class_decoded
		end
	  else
	    return "DEATHKNIGHT"
	  end
    end
  end
end

local function EncodeNote(ep, gp, alt)
  if alt == 0 then
    return string.format("%d,%d",
						   math.max(ep, 0),
						   math.max(gp - global_config.base_gp, 0))
  else
    return string.format("%d,%d;%s/%s",
						   math.max(ep, 0),
						   math.max(gp - global_config.base_gp, 0),
						   alt,
						   encode_class[oog_alts[alt]["class"]] or "dh")
  end
end

local function AddEPGP(name, ep, gp)
  local total_ep = ep_data[name]
  local total_gp = gp_data[name]
  assert(total_ep ~= nil and total_gp ~=nil,
         string.format("%s is not a main!", tostring(name)))

  -- Compute the actual amounts we can add/subtract.
  if (total_ep + ep) < 0 then
    ep = -total_ep
  end
  if (total_gp + gp) < 0 then
    gp = -total_gp
  end
  if oog_main_alt_list[name] then
    GS:SetNote(name, EncodeNote(total_ep + ep,
                              total_gp + gp + global_config.base_gp, oog_main_alt_list[name]))
  else
    GS:SetNote(name, EncodeNote(total_ep + ep,
                              total_gp + gp + global_config.base_gp, 0))
  end
  return ep, gp
end

-- A wrapper function to handle sort logic for selected
local function ComparatorWrapper(f)
  return function(a, b)
           local a_in_raid = not not UnitInRaid(a)
           local b_in_raid = not not UnitInRaid(b)
           if a_in_raid ~= b_in_raid then
             return not b_in_raid
           end

           local a_selected = selected[a]
           local b_selected = selected[b]

           if a_selected ~= b_selected then
             return not b_selected
           end

           return f(a, b)
         end
end

local comparators = {
  NAME = function(a, b)
           return a < b
         end,
  EP = function(a, b)
         local a_ep, a_gp = EPGP:GetEPGP(a)
         local b_ep, b_gp = EPGP:GetEPGP(b)

         return a_ep > b_ep
       end,
  GP = function(a, b)
         local a_ep, a_gp = EPGP:GetEPGP(a)
         local b_ep, b_gp = EPGP:GetEPGP(b)

         return a_gp > b_gp
       end,
  PR = function(a, b)
         local a_ep, a_gp = EPGP:GetEPGP(a)
         local b_ep, b_gp = EPGP:GetEPGP(b)

         local a_qualifies = a_ep >= global_config.min_ep
         local b_qualifies = b_ep >= global_config.min_ep

         if a_qualifies == b_qualifies then
           return a_ep/a_gp > b_ep/b_gp
         else
           return a_qualifies
         end
       end,
}
for k,f in pairs(comparators) do
  comparators[k] = ComparatorWrapper(f)
end

local function DestroyStandings()
  wipe(standings)
  callbacks:Fire("StandingsChanged")
end

local function RefreshStandings(order, showEveryone)
  Debug("Resorting standings")
  if UnitInRaid("player") then
    -- If we are in raid:
    ---  showEveryone = true: show all in raid (including alts) and
    ---  all leftover mains
    ---  showEveryone = false: show all in raid (including alts) and
    ---  all selected members
    for n in pairs(ep_data) do
      if showEveryone or UnitInRaid(n) or selected[n] then
        table.insert(standings, n)
      end
    end
    for n in pairs(main_data) do
      if UnitInRaid(n) or selected[n] then
        table.insert(standings, n)
      end
    end
  else
    -- If we are not in raid, show all mains
    for n in pairs(ep_data) do
      table.insert(standings, n)
    end
  end

  -- Sort
  table.sort(standings, comparators[order])
end

-- Parse options. Options are inside GuildInfo and are inside a -EPGP-
-- block. Possible options are:
--
-- @DECAY_P:<number>
-- @EXTRAS_P:<number>
-- @MIN_EP:<number>
-- @BASE_GP:<number>
local global_config_defs = {
  decay_p = {
    pattern = "@DECAY_P:(%d+)",
    parser = tonumber,
    validator = function(v) return v >= 0 and v <= 100 end,
    error = L["Decay Percent should be a number between 0 and 100"],
    default = 0,
    change_message = "DecayPercentChanged",
  },
  extras_p = {
    pattern = "@EXTRAS_P:(%d+)",
    parser = tonumber,
    validator = function(v) return v >= 0 and v <= 100 end,
    error = L["Extras Percent should be a number between 0 and 100"],
    default = 100,
    change_message = "ExtrasPercentChanged",
  },
  min_ep = {
    pattern = "@MIN_EP:(%d+)",
    parser = tonumber,
    validator = function(v) return v >= 0 end,
    error = L["Min EP should be a positive number"],
    default = 0,
    change_message = "MinEPChanged",
  },
  base_gp = {
    pattern = "@BASE_GP:(%d+)",
    parser = tonumber,
    validator = function(v) return v >= 0 end,
    error = L["Base GP should be a positive number"],
    default = 1,
    change_message = "BaseGPChanged",
  },
}
-- Set defaults
for var, def in pairs(global_config_defs) do
  global_config[var] = def.default
end

function mysplit (inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                table.insert(t, str)
        end
        return t
end


local function ParseGuildInfo(callback, info)
  Debug("Parsing GuildInfo")
  local lines = {string.split("\n", info)}
  local in_block = false
  local in_alt = false

  local new_config = {}

  for _,line in pairs(lines) do
    if line == "-EPGP-" then
      in_block = not in_block
    elseif in_block then
      for var, def in pairs(global_config_defs) do
        local v = line:match(def.pattern)
        if v then
          Debug("Matched [%s]", line)
          v = def.parser(v)
          if v == nil or not def.validator(v) then
            EPGP:Print(def.error)
          else
            new_config[var] = v
          end
        end
      end
    end
  end
  
   for _,line in pairs(lines) do
    if line == "-EPGP_ALTS-" then
      in_alt = not in_alt
    elseif in_alt then
        local v = mysplit(line, ";")
		Debug("guild info line %s", line)
        if v then
			local main_char = table.remove(v,1)
			for key,value in pairs(v) do
				local alt_char = mysplit(value,"/")[1]
				local alt_class = decode_class[mysplit(value,"/")[2]]
				Debug("main_char [%s]", (main_char))
				if ep_data[main_char] then
					Debug("Main char exist")
				end
				Debug("alt_char [%s]", (alt_char))
				Debug("alt_class [%s]", (alt_class))
				main_data[alt_char] = main_char
				if not alt_data[main_char] then
				  alt_data[main_char] = {}
				end
				table.insert(alt_data[main_char], alt_char)
				ep_data[alt_char] = nil
				gp_data[alt_char] = nil
				oog_alts[alt_char] = {}
				oog_alts[alt_char]["class"] = alt_class
				oog_alts[alt_char]["rank"] = GS:GetRank(main_char)
				oog_alts[alt_char]["main"] = main_char
			--[[
			Debug("Matched [%s]", line)
			v = def.parser(v)
			--todo have it check the main exists
			if v == nil or not def.validator(v) then
			EPGP:Print(def.error)
			else
			new_config[var] = v
			end--]]
			end
        end
	  
    end
  end

  for var, def in pairs(global_config_defs) do
    local new_value = new_config[var]
    if new_value == nil then
      new_value = def.default
    end
    if global_config[var] ~= new_value then
      Debug("Setting new value %s for variable %s",
            tostring(new_value), var)
      global_config[var] = new_value
      callbacks:Fire(def.change_message, new_value)
    end
  end
end

local function DeleteState(name)
  ignored[name] = nil
  -- If this is was an alt we need to fix the alts state
  local main = main_data[name]
  if main then
    if alt_data[main] then
      for i,alt in ipairs(alt_data[main]) do
        if alt == name then
          table.remove(alt_data[main], i)
          break
        end
      end
    end
    main_data[name] = nil
  end
  -- Delete any existing cached values
  ep_data[name] = nil
  gp_data[name] = nil
end

local function HandleDeletedGuildNote(callback, name)
  DeleteState(name)
  DestroyStandings()
end

local function ParseGuildNote(callback, name, note)
  Debug("Parsing Guild Note for %s [%s]", name, note)
  -- Delete current state about this toon.
  DeleteState(name)

  local ep, gp, alt = DecodeNote(note)
  if alt ~= 0 then
    Debug("Alt detected %s", alt)
    -- used for out of guild alts, means a name of a alt has been returned
	main_data[alt] = name
	-- todo bug here
    if not alt_data[name] then
      alt_data[name] = {}
    end
    table.insert(alt_data[name], alt)
	oog_main_alt_list[name] = alt
	oog_alts[alt] = {}
	oog_alts[alt]["class"] = ScrapeClass(note)
	oog_alts[alt]["rank"] = GS:GetRank(name)
	oog_alts[alt]["main"] = name
	-- todo table.insert(oog_main_alt_list[name], alt)
    ep_data[alt] = nil
    gp_data[alt] = nil
	ep_data[name] = ep
    gp_data[name] = gp
  else
    if ep then
      ep_data[name] = ep
      gp_data[name] = gp
    else
      local main_ep = DecodeNote(GS:GetNote(note))
      if not main_ep then
        -- This member does not point to a valid main, ignore it.
        ignored[name] = note
      else
        -- Otherwise setup the alts state
        main_data[name] = note
        if not alt_data[note] then
          alt_data[note] = {}
        end
        table.insert(alt_data[note], name)
        ep_data[name] = nil
        gp_data[name] = nil
      end
    end
  end
  DestroyStandings()
end

function EPGP:ExportRoster()
  local base_gp = global_config.base_gp
  local t = {}
  for name,_ in pairs(ep_data) do
    local ep, gp, main = self:GetEPGP(name)
    if ep ~= 0 or gp ~= base_gp then
      table.insert(t, {name, ep, gp})
    end
  end
  return t
end

function EPGP:ImportRoster(t, new_base_gp)
  --todo modify
  -- This ugly hack is because EncodeNote reads base_gp to encode the
  -- GP properly. So we reset it to what we get passed, and then we
  -- restore it so that the BaseGPChanged event is fired properly when
  -- we parse the guild info text after this function returns.
  local old_base_gp = global_config.base_gp
  global_config.base_gp = new_base_gp

  local notes = {}
  for _, entry in pairs(t) do
    local name, ep, gp = unpack(entry)
	if oog_main_alt_list[name] then
	  notes[name] = EncodeNote(ep, gp, oog_main_alt_list[name])
	else
      notes[name] = EncodeNote(ep, gp, 0)
	end
  end

  local zero_note = EncodeNote(0, 0, 0)
  for name,_ in pairs(ep_data) do
    local note = notes[name] or zero_note
    GS:SetNote(name, note)
  end

  global_config.base_gp = old_base_gp
end

function EPGP:StandingsSort(order)
  if not order then
    return db.profile.sort_order
  end

  assert(comparators[order], "Unknown sort order")

  db.profile.sort_order = order
  DestroyStandings()
end

function EPGP:StandingsShowEveryone(val)
  if val == nil then
    return db.profile.show_everyone
  end

  db.profile.show_everyone = not not val
  DestroyStandings()
end

function EPGP:GetNumMembers()
  if #standings == 0 then
    RefreshStandings(db.profile.sort_order, db.profile.show_everyone)
  end

  return #standings
end

function EPGP:GetMember(i)
  if #standings == 0 then
    RefreshStandings(db.profile.sort_order, db.profile.show_everyone)
  end

  return standings[i]
end

function EPGP:GetNumAlts(name)
  local alts = alt_data[name]
  if not alts then
    return 0
  else
    return #alts
  end
end

function EPGP:GetAlt(name, i)
  return alt_data[name][i]
end

function EPGP:GetRank(name)
	if oog_alts[name] ~= nil then
		return oog_alts[name]["rank"]
	else
		return GS:GetRank(name)
	end
end

function EPGP:GetMain(name)
  if oog_alts[name] ~= nil then
    return oog_alts[name]["main"]
  else
    return 'Is Main'
  end
end

function EPGP:SelectMember(name)
  if UnitInRaid("player") then
    -- Only allow selecting members that are not in raid when in raid.
    if UnitInRaid(name) then
      return false
    end
  end
  selected[name] = true
  selected._count = selected._count + 1
  DestroyStandings()
  return true
end

function EPGP:DeSelectMember(name)
  if UnitInRaid("player") then
    -- Only allow deselecting members that are not in raid when in raid.
    if UnitInRaid(name) then
      return false
    end
  end
  if not selected[name] then
    return false
  end
  selected[name] = nil
  selected._count = selected._count - 1
  DestroyStandings()
  return true
end

function EPGP:GetNumMembersInAwardList()
  if UnitInRaid("player") then
    return GetNumRaidMembers() + selected._count
  else
    if selected._count == 0 then
      return self:GetNumMembers()
    else
      return selected._count
    end
  end
end

function EPGP:IsMemberInAwardList(name)
  if UnitInRaid("player") then
    -- If we are in raid the member is in the award list if it is in
    -- the raid or the selected list.
    return UnitInRaid(name) or selected[name]
  else
    -- If we are not in raid and there is noone selected everyone will
    -- get an award.
    if selected._count == 0 then
      return true
    end
    return selected[name]
  end
end

function EPGP:IsMemberInExtrasList(name)
  return UnitInRaid("player") and selected[name]
end

function EPGP:IsAnyMemberInExtrasList()
  return selected._count ~= 0
end

function EPGP:CanResetEPGP()
  return CanEditOfficerNote() and GS:IsCurrentState()
end

function EPGP:ResetEPGP()
  assert(EPGP:CanResetEPGP())
  --todo retain alts after reset
  for name,_ in pairs(ep_data) do
    local zero_note = EncodeNote(0, 0, 0)
    if oog_main_alt_list[name] ~= nil then
	  zero_note = EncodeNote(0, 0, oog_main_alt_list[name])
	end
    GS:SetNote(name, zero_note)
    local ep, gp, main = self:GetEPGP(name)
    assert(main == nil, "Corrupt alt data!")
    if ep > 0 then
      callbacks:Fire("EPAward", name, "Reset", -ep, true)
    end
    if gp > 0 then
      callbacks:Fire("GPAward", name, "Reset", -gp, true)
    end
  end
  callbacks:Fire("EPGPReset")
end

function EPGP:CanDecayEPGP()
  if not CanEditOfficerNote() or global_config.decay_p == 0 or not GS:IsCurrentState() then
    return false
  end
  return true
end

function EPGP:DecayEPGP()
  assert(EPGP:CanDecayEPGP())

  local decay = global_config.decay_p  * 0.01
  local reason = string.format("Decay %d%%", global_config.decay_p)
  for name,_ in pairs(ep_data) do
    local ep, gp, main = self:GetEPGP(name)
    assert(main == nil, "Corrupt alt data!")
    local decay_ep = math.ceil(ep * decay)
    local decay_gp = math.ceil(gp * decay)
    decay_ep, decay_gp = AddEPGP(name, -decay_ep, -decay_gp)
    if decay_ep ~= 0 then
      callbacks:Fire("EPAward", name, reason, decay_ep, true)
    end
    if decay_gp ~= 0 then
      callbacks:Fire("GPAward", name, reason, decay_gp, true)
    end
  end
  callbacks:Fire("Decay", global_config.decay_p)
end

function EPGP:GetEPGP(name)
  local main = main_data[name]
  if main then
    name = main
  end
  if ep_data[name] then
    return ep_data[name], gp_data[name] + global_config.base_gp, main
  end
end

function EPGP:GetMembers()
	return ep_data
end

function EPGP:GetClass(name)
  if oog_alts[name] ~= nil then
    return oog_alts[name]["class"]
  end
  return GS:GetClass(name)
end

function EPGP:CanIncEPBy(reason, amount)
  if not CanEditOfficerNote() or not GS:IsCurrentState() then
    return false
  end
  if type(reason) ~= "string" or type(amount) ~= "number" or #reason == 0 then
    return false
  end
  if amount ~= math.floor(amount + 0.5) then
    return false
  end
  if amount < -99999 or amount > 99999 or amount == 0 then
    return false
  end
  return true
end

function EPGP:IncEPBy(name, reason, amount, mass, undo)
  -- When we do mass EP or decay we know what we are doing even though
  -- CanIncEPBy returns false
  assert(EPGP:CanIncEPBy(reason, amount) or mass or undo)
  assert(type(name) == "string")

  local ep, gp, main = self:GetEPGP(name)
  if not ep then
    self:Print(L["Ignoring EP change for unknown member %s"]:format(name))
    return
  end
  amount = AddEPGP(main or name, amount, 0)
  if amount then
    callbacks:Fire("EPAward", name, reason, amount, mass, undo)
  end
  db.profile.last_awards[reason] = amount
  return main or name
end

function EPGP:CanIncGPBy(reason, amount)
  if not CanEditOfficerNote() or not GS:IsCurrentState() then
    return false
  end
  if type(reason) ~= "string" or type(amount) ~= "number" or #reason == 0 then
    return false
  end
  if amount ~= math.floor(amount + 0.5) then
    return false
  end
  if amount < -99999 or amount > 99999 or amount == 0 then
    return false
  end
  return true
end

function EPGP:IncGPBy(name, reason, amount, mass, undo)
  -- When we do mass GP or decay we know what we are doing even though
  -- CanIncGPBy returns false
  assert(EPGP:CanIncGPBy(reason, amount) or mass or undo)
  assert(type(name) == "string")

  local ep, gp, main = self:GetEPGP(name)
  if not ep then
    self:Print(L["Ignoring GP change for unknown member %s"]:format(name))
    return
  end
  _, amount = AddEPGP(main or name, 0, amount)
  if amount then
    callbacks:Fire("GPAward", name, reason, amount, mass, undo)
  end

  return main or name
end

function EPGP:BankItem(reason, undo)
  callbacks:Fire("BankedItem", GUILD_BANK, reason, 0, false, undo)
end

function EPGP:GetDecayPercent()
  return global_config.decay_p
end

function EPGP:GetExtrasPercent()
  return global_config.extras_p
end

function EPGP:GetBaseGP()
  return global_config.base_gp
end

function EPGP:GetMinEP()
  return global_config.min_ep
end

function EPGP:SetGlobalConfiguration(decay_p, extras_p, base_gp, min_ep)
  local guild_info = GS:GetGuildInfo()
  epgp_stanza = string.format(
    "-EPGP-\n@DECAY_P:%d\n@EXTRAS_P:%s\n@MIN_EP:%d\n@BASE_GP:%d\n-EPGP-",
    decay_p or DEFAULT_DECAY_P,
    extras_p or DEFAULT_EXTRAS_P,
    min_ep or DEFAULT_MIN_EP,
    base_gp or DEFAULT_BASE_GP)

  -- If we have a global configuration stanza we need to replace it
  Debug("epgp_stanza:\n%s", epgp_stanza)
  if guild_info:match("%-EPGP%-.*%-EPGP%-") then
    guild_info = guild_info:gsub("%-EPGP%-.*%-EPGP%-", epgp_stanza)
  else
    guild_info = epgp_stanza.."\n"..guild_info
  end
  Debug("guild_info:\n%s", guild_info)
  SetGuildInfoText(guild_info)
  GuildRoster()
end

function EPGP:GetMain(name)
  return main_data[name] or name
end

function EPGP:IncMassEPBy(reason, amount, manual)
  local awarded = {}
  local extras_awarded = {}
  local extras_amount = math.floor(global_config.extras_p * 0.01 * amount)
  local extras_reason = reason .. " - " .. L["Standby"]
  
  for i=1,EPGP:GetNumMembers() do
    local name = EPGP:GetMember(i)
	mlzone = GetRealZoneText()
	zone=''
	inzone=false
	if UnitIsConnected(name)==1 then
		online = true
		for i=1, GetNumRaidMembers() do
			name1, rank, subgroup, level, class, fileName, zone1,_ = GetRaidRosterInfo(i)
			if name==name1 then
				zone = zone1 
				if zone==mlzone then
					inzone=true
				end
			end
		end
	else
		online = false
	end
	if EPGP.db.profile.inzone == false then
		inzone = true
	end
	if EPGP.db.profile.offline == false then
		online = true
	end
	--[[if not manual then
		inzone = true
		online = true
		EPGP:Print("Not manual")
	end
	--if online and inzone then
	--	EPGP:Print(name, zone, mlzone)
	--else
	--needs a prompt
	--	a = 1
	end--]]
    if EPGP:IsMemberInAwardList(name) and ((online and inzone) or not manual) then
      -- EPGP:GetMain() will return the input name if it doesn't find a main,
      -- so we can't use it to validate that this actually is a character who
      -- can recieve EP.
      --
      -- EPGP:GetEPGP() returns nil for ep and gp, if it can't find a
      -- valid member based on the name however.
      local ep, gp, main = EPGP:GetEPGP(name)
      local main = main or name
      if ep and not awarded[main] and not extras_awarded[main] then
        if EPGP:IsMemberInExtrasList(name) then
          EPGP:IncEPBy(name, extras_reason, extras_amount, true)
          extras_awarded[name] = true
        else
          EPGP:IncEPBy(name, reason, amount, true)
          awarded[name] = true
        end
      end
    end
  end
  if next(awarded) then
    if next(extras_awarded) then
      callbacks:Fire("MassEPAward", awarded, reason, amount,
                     extras_awarded, extras_reason, extras_amount)
    else
      callbacks:Fire("MassEPAward", awarded, reason, amount)
    end
  end
end

function EPGP:ReportErrors(outputFunc)
  for name, note in pairs(ignored) do
    outputFunc(L["Invalid officer note [%s] for %s (ignored)"]:format(
                 note, name))
  end
end

function EPGP:OnInitialize()
  -- Setup the DB. The DB will NOT be ready until after OnEnable is
  -- called on EPGP. We do not call OnEnable on modules until after
  -- the DB is ready to use.
  db = LibStub("AceDB-3.0"):New("EPGP_DB")

  local defaults = {
    profile = {
      last_awards = {},
      show_everyone = false,
      sort_order = "PR",
      recurring_ep_period_mins = 15,
	  offline = false,
	  inzone = false,
    }
  }
  db:RegisterDefaults(defaults)
  for name, module in self:IterateModules() do
    -- Each module gets its own namespace. If a module needs to set
    -- defaults, module.dbDefaults needs to be a table with
    -- defaults. Otherwise we initialize it to be enabled by default.
    if not module.dbDefaults then
      module.dbDefaults = {
        profile = {
          enabled = true
        }
      }
    end
    module.db = db:RegisterNamespace(name, module.dbDefaults)
  end
  -- After the database objects are created, we setup the
  -- options. Each module can inject its own options by defining:
  --
  -- * module.optionsName: The name of the options group for this module
  -- * module.optionsDesc: The description for this options group [short]
  -- * module.optionsArgs: The definition of this option group
  --
  -- In addition to the above EPGP will add an Enable checkbox for
  -- this module. It is also guaranteed that the name of the node this
  -- group will be in, is the same as the name of the module. This
  -- means you can get the name of the module from the info table
  -- passed to the callback functions by doing info[#info-1].
  --
  self:SetupOptions()

  -- New version note.
  if db.global.last_version ~= EPGP.version then
    db.global.last_version = EPGP.version
    StaticPopup_Show("EPGP_NEW_VERSION")
  end
end

function EPGP:RAID_ROSTER_UPDATE()
  if UnitInRaid("player") then
    -- If we are in a raid, make sure no member of the raid is
    -- selected
    for name,_ in pairs(selected) do
      if UnitInRaid(name) then
        selected[name] = nil
        selected._count = selected._count - 1
      end
    end
  else
    -- If we are not in a raid, this means we just left so remove
    -- everyone from the selected list.
    wipe(selected)
    selected._count = 0
    -- We also need to stop any recurring EP since they should stop
    -- once a raid stops.
    if self:RunningRecurringEP() then
      self:StopRecurringEP()
    end
  end
  DestroyStandings()
end

function EPGP:GUILD_ROSTER_UPDATE()
  if not IsInGuild() then
    for name, module in EPGP:IterateModules() do
      module:Disable()
    end
  else
    local guild = GetGuildInfo("player") or ""
    if #guild == 0 then
      GuildRoster()
    else
      if db:GetCurrentProfile() ~= guild then
        Debug("Setting DB profile to: %s", guild)
        db:SetProfile(guild)
      end
      -- This means we didn't initialize the db yet.
      if not EPGP.db then
        EPGP.db = db

        -- Enable all modules that are supposed to be enabled
        for name, module in EPGP:IterateModules() do
          if module.db.profile.enabled or not module.dbDefaults then
            Debug("Enabling module (startup): %s", name)
            module:Enable()
          end
        end
        -- Check if we have a recurring award we can resume
        if EPGP:CanResumeRecurringEP() then
          EPGP:ResumeRecurringEP()
        else
          EPGP:CancelRecurringEP()
        end
      end
    end
  end
end

function EPGP:OnEnable()
  GS.RegisterCallback(self, "GuildInfoChanged", ParseGuildInfo)
  GS.RegisterCallback(self, "GuildNoteChanged", ParseGuildNote)
  GS.RegisterCallback(self, "GuildNoteDeleted", HandleDeletedGuildNote)

  EPGP.RegisterCallback(self, "BaseGPChanged", DestroyStandings)

  self:RegisterEvent("RAID_ROSTER_UPDATE")
  self:RegisterEvent("GUILD_ROSTER_UPDATE")

  GuildRoster()
end
