-- Copyright 2006-2009 Riccardo Belloli (rb@belloli.net)
-- This file is a part of QDKP_V2 (see about.txt in the Addon's root folder)

--             ## EXPORTER ##
--
--      Outputs a table of all the DKP values for the guild or raid members.
--      it can uses the ASCII or the HTML backend to produce the table.

--  API Documentation:







------------------------------------- LOCALS-----------------------

local function ColortableToHtml(colorTable)
  local num=colorTable.b*255
  local num=num+bit.band(colorTable.g*65280,0xFF00)
  local num=num+bit.band(colorTable.r*16711680,0xFF0000)
  local str=string.format("%X",num)
  return "#"..string.rep("0",6-#str)..str
end

local GenericXMLHeader='<?xml version="1.0" encoding="ISO-8859-1" ?>'

--returns a copy of the list. if destList is given copies the data there.
function EPGP_CopyTable(list,destList)
  local output = destList or {}
  for i,v in pairs(list) do output[i]=v; end
  return output
end

local function DecodeItemLink(str,format)
--reformats al item links in the text to be human readable
	repeat
		local istart, istop, istring = string.find(str, "|c%x+|H(.+)|h%[.*%]|h|r")
		if istart then
			local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(istring)
			if format=="html" and itemName then
				local _, itemId, enchantId, jewelId1, jewelId2, jewelId3, jewelId4, suffixId, uniqueId, linkLevel = string.split(":", istring)
				local _,_,_,color=GetItemQualityColor(itemRarity)
				color=string.sub(color,5)
				ilink=string.format('<a href="https://db.rising-gods.de/?item=%s"><font color="#%s"><b>[%s]</b></font></a>',itemId,color,itemName)
			else
				ilink=string.format('[%s]',tostring(itemName))
			end
			str=string.sub(str,1,istart-1)..ilink..string.sub(str,istop+1)
		end
	until not istart
	return str
end



--Generic exporter prototype
local GenericExporter={}
GenericExporter.Formats={"Text","HTML","XML"}
function GenericExporter:GetData(EntryList,Format)
	local rowList={}
	for i,x in ipairs(EntryList) do
		local row={}
		for j,culumn in ipairs(self.Columns) do
			if not culumn.isDisabled or not culumn.isDisabled(x,Format) then
				local cell=culumn.query(x,Format)
				table.insert(row,cell)
			end
		end
		table.insert(rowList,row)
	end
	return rowList
end

--Export
function GenericExporter:MakeTable(Format,rowList)
	local width={}
	table.insert(rowList,1,{}) --making room for header
	for i,culumn in ipairs(self.Columns) do
		if not culumn.isDisabled or not culumn.isDisabled(x,Format) then
			table.insert(width,culumn.width)
			table.insert(rowList[1],culumn.header)
			rowList[1].color='#E5D000'
		end
	end
  if Format=='text' then
		return EPGP_BuildAsciiTable(rowList,width,true,true)
  elseif Format=='html' then
		return EPGP_BuildHtmlTable(rowList,'#FFFFFF','#202020','#B0B0B0',true,true)
  end
end

function GenericExporter:MakeXML(rowList)
	local out=''
	for i,row in ipairs(rowList) do
		out=out.."  <"..self.XMLRowVoiceName.." "
		for j,cell in ipairs(row) do
			local header=self.Columns[j].xmlHeader
			if cell then out=out..header..'="'..tostring(cell)..'" '
			end
		end
		out=out..'/>\n'
	end
	return out
end

--Column
function GenericExporter:MakeHeader(Format,Header)
	local out=Header or ''
	if Format=='html' then
		out=out:gsub("<","&lt;")
		out=out:gsub(">","&gt;")
		out=string.gsub(out,'EPGP','<A HREF="https://github.com/vorghahn/EPGP/releases/latest/download/EPGP.zip">EPGP</A>')
	end
	out=string.gsub(out,"$TIME",date())
	out=string.gsub(out,"$GUILDNAME",EPGP_GUILD_NAME or '')
	if Format=='text' then
		out=out..'\n\n[CODE]\n'
	elseif Format=='html' then
		out=out..'\n<BR><BR>\n'
	end
	return out
end

function GenericExporter:MakeTail(Format,Tail)
	out=Tail or ''
	if Format=='text' then
		out=out..'\n[/CODE]'
	end
	return out
end


--Guild roster DKP exporter
local GuildExport=EPGP_CopyTable(GenericExporter)
function GuildExport:Export(Format)
	local num_mem = EPGP:GetNumMembers()
	local nameList = {}
	for i=1,num_mem do
		table.insert(nameList, EPGP:GetMember(i))
	end
	local out
	local rowList=self:GetData(nameList,Format)
	if Format=='xml' then
		out=GenericXMLHeader..'\n'
		out=out..'<EPGP-EXPORT list="guild" time="'..time()..'" guild="'..tostring(GetGuildInfo("player"))..'" exporter="'..tostring(UnitName('player'))..'" >\n'
		out=out..self:MakeXML(rowList)
		out=out..'</EPGP-EXPORT>'
	else
		header=self:MakeHeader(Format,EPGP_Export_TXT_Header)
		body=self:MakeTable(Format,rowList,width).."\n"
		tail=self:MakeTail(Format)
		out=header..body..tail
	end
	return out
end

function GuildExport:GetMembers() return EPGP:GetMembers(); end

GuildExport.XMLRowVoiceName="PLAYER"
GuildExport.Columns={
	{
		header = "Name",
		xmlHeader="name",
		width = 24,
		query = function(name,Format)
			if Format=='html' then
				return '<B>'..name..'</B>'
			elseif Format=='xml' then
				return name
			else
				return name; --EPGP_GetName(name);
			end
		end,
	},
	{
		header = "Main",
		xmlHeader = "main",
		query = function(name,Format)
		  return EPGP:GetMain(name) or false
		end,
		isDisabled = function(name,Format) if Format=="xml" then return false; end; return true; end,
	},
	{
		header = "Class",
		xmlHeader="class",
		width = 16,
		query = function(name,Format)
			if Format=='html' then
				local class=EPGP:GetClass(name) or ""
				colors=RAID_CLASS_COLORS[class]
				return '<FONT color="'..ColortableToHtml(colors)..'">'..(EPGP:GetClass(name) or '-')..'</FONT>'
			else
				return EPGP:GetClass(name)
			end
		end,
	},
	{
		header = "Rank",
		xmlHeader="rank",
		width = 12,
		query = function(name)
			return EPGP:GetRank(name) or ''
		end,
	},
	{
		header = "EP",
		xmlHeader="ep",
		width = 9,
		query = function(name,Format)
			ep, gp, main = EPGP:GetEPGP(name)
			if ep<0 and Format=='html' then
				ep='<FONT COLOR="red">'..tostring(ep)..'</FONT>'
			end
			return ep
		end,
	},
	{
		header = "GP",
		xmlHeader="gp",
		width = 9,
		query = function(name)
			ep, gp, main = EPGP:GetEPGP(name)
			return gp
		end,
	}
}

--Raid roster DKP exporter
local RaidExport=EPGP_CopyTable(GuildExport)
function RaidExport:GetMembers() return EPGPraid; end

--LogList exporter
local LogListExport=EPGP_CopyTable(GenericExporter)
LogListExport.Formats={"Text","HTML"}
function LogListExport:Export(Format,LogList)
	local rowList=self:GetData(LogList,Format)
	for i=1,#LogList do
		rowList[i].color=ColortableToHtml(EPGPlog_GetEntryColor(EPGPlog_GetType(LogList[i])))
	end
	header=self:MakeHeader(Format,LogExport_TXT_Header)
	body=self:MakeTable(Format,rowList,width).."\n"
	tail=self:MakeTail(Format)
	return header..body..tail
end

LogListExport.Columns={
	{header="Time",
	xmlHeader="timestamp",
	width=12,
	query=function(log,Format)
		local ts=EPGPlog_GetTS(log)
		if Format=="xml" then return ts
		else return EPGP_GetDateTextFromTS(ts)
		end
	end,
	},
	{header="DKP Change",
		xmlHeader="change",
		width=10,
		query=function(log) return EPGPlog_GetChange(log) or ''; end,
	},
	{header="Description",
		xmlHeader="description",
		width=42,
		query=EPGPlog_GetModEntryText,
	},
}

--Log Session exporter
local LogSessionExport=EPGP_CopyTable(LogListExport)
function LogSessionExport:Export(Format,SID)
	local LogList=EPGPlog_GetPlayer(SID,"RAID")
	if not LogList then return ''; end
	return LogListExport:Export(Format,LogList)
end


--Extended Log Session exporter
local ExtLogSessionExport=EPGP_CopyTable(LogListExport)
function ExtLogSessionExport:Export(Format,SID)
	local LogList,NameList=EPGPlog_GetSessionDetails(SID)
	EPGP_Export_PlayerNames=NameList
	--local turn={}
	--for i,v in ipairs(LogList) do turn[#LogList-i+1]=v; end
	--LogList=turn
	return LogListExport.Export(self,Format,LogList)
end

ExtLogSessionExport.Columns=EPGP_CopyTable(LogListExport.Columns)
table.insert(ExtLogSessionExport.Columns,2,{
	header="Player",
	xmlHeader="player",
	width=24,
	query=function(log,Format)
		local name=EPGP_Export_PlayerNames[log]
		if name~=RAID then name=EPGP_FormatName(name); end
		return name or ''
		end,
})

local ExporterList={
	guild=GuildExport,
	raid=RaidExport,
	loglist=LogListExport,
	logsession=LogSessionExport,
	extlogsession=ExtLogSessionExport,
}

function EPGP:EPGP_Export_Popup(Type,Format,OptPar)
	local obj=ExporterList[Type]
	if not obj then
		EPGP_Debug(1,"Core","Asked for unknow export type: "..tostring(Type))
		return
	end
	EPGP_Export_Type=Type
	EPGP_Export_OptPar=OptPar
	Format=Format or obj.Formats[1]
	EPGP_CopyWindow_FormatManager=EPGP_Export_ManageCheckBox
	EPGP_Export_ManageCheckBox(Format)
end


function EPGP_Export_ManageCheckBox(Format)
	local obj=ExporterList[EPGP_Export_Type]
	if not obj then
		EPGP_Debug(1,"Core","Asked for unknow export type: "..tostring(Type))
		return
	end
	local formatName
	for i=1,4 do
    local f=obj.Formats[i]
    local check=getglobal("EPGP_CopyWindow_Format"..i)
    local checkText=getglobal("EPGP_CopyWindow_Format"..i.."Text")
    if f then
		check:Show()
		checkText:SetText(f)
		if i==Format or string.lower(f)==string.lower(Format) then
			formatName=string.lower(f)
			check:SetChecked(true)
		else
			check:SetChecked(false)
		end
    else
		check:Hide()
		end
	end
	local Text=''
	if not formatName then
		EPGP_Debug(1,"Core","Asked for unsupported export format: "..tostring(Format))
	else
		Text=EPGP_Export(EPGP_Export_Type,formatName,EPGP_Export_OptPar)
	end
	EPGP_OpenCopyWindow(Text,true)
end


function EPGP_Export(Type,Format,OptPar)
	local obj=ExporterList[Type]
	if not obj then
		EPGP_Debug(1,"Core","Asking for unknow export type: "..tostring(Type))
		return
	end
	return obj:Export(Format,OptPar)
end

function EPGP_OpenCopyWindow(text,showCheckBox)
	EPGP_CopyWindow_LinesNum=1
	for i=1,#text do
		if string.sub(text,i,i)=='\n' then EPGP_CopyWindow_LinesNum=EPGP_CopyWindow_LinesNum+1; end
	end
	EPGP_CopyWindow_TextBuff=text
	EPGP_CopyWindow:Show()
	EPGP_CopyWindow_text:SetText("Press CTRL+C on the keyboard to copy the export in your clipboard.")
	EPGP_CopyWindow_Data:SetText(EPGP_CopyWindow_TextBuff)
	EPGP_CopyWindow_Data:HighlightText()
	EPGP_CopyWindow_Data:SetFocus()
end

------------ Helper functions ----------------


local nl='\n'

-- this function builds a table made with ascii characters.
-- rowList should have all the lines to be inserted in the table, and
-- all rows must be lists with the cells content.
-- culWidth is a list with the width, in characters, of each culumn
-- header: if true, the first row in list is treated as table header.
-- rowBord: if true and is a number, each n row a horizontal line is placed.
-- culBord: if true, each culumn is separed from each other by a line

function EPGP_FormatName(name)
--formats the name properly.  ie airiena would become Airiena
--Unicode compatible

  assert(type(name)=='string')
  if #name<1 then return ""; end
  if #name==1 then return string.upper(name); end
  local till=1
  for i=1,#name do  --this is to get the real first character (UTF8)
    --if i==#name then return string.upper(name); end
    local char=strbyte(name,i+1)
    if not char or (char<128 or char>191)  then break; end
    i=i+1
    till=i
  end
  local first = string.sub(name, 1, till)
  local remainder = string.sub(name, 2)
  local output = string.upper(first)..string.lower(remainder)
  return output
end


function EPGP_UTF8len(str)
  if #str<=1 then return #str; end
  l=0
  for i=1,#str do
    local char=strbyte(str,i)
    if char<128 or (char>193 and char<245) then l=l+1; end
  end
  return l
end


function EPGP_CutString(txt,len)
-- Cuts txt if is longer than len, adding two dots at the end.
  if #txt>len then
    txt=string.sub(txt,1,len-2)..'..'
  end
  return txt
end

function EPGP_CenterString(txt,len)
--This adds whitespaces before and after txt to center it in a field of len characters
  local sect=len-EPGP_UTF8len(txt)
  txt=string.rep(' ',math.floor(sect/2))..txt..string.rep(' ',math.ceil(sect/2))
  return txt
end


function EPGP_SplitString(txt,delimiter)
--returns a list of substring of txt usind delimeter to break them.
  local result = { }
  local from  = 1
  local delim_from, delim_to = string.find( txt, delimiter, from  )
  while delim_from do
    table.insert( result, string.sub( txt, from , delim_from-1 ) )
    from  = delim_to + 1
    delim_from, delim_to = string.find( txt, delimiter, from  )
  end
  table.insert( result, string.sub( txt, from  ) )
  return result
end

local function makeTextLine(line,culWidth,culBord)
    local sep=''
    if culBord then sep = '|'; end
    local out='|'
    for i=1,#culWidth do
		local cw=culWidth[i]
		local cell=DecodeItemLink(tostring(line[i] or ''))
		local cell=EPGP_CenterString(EPGP_CutString(cell,cw),cw)
		out=out..cell..sep
    end
    if not culBord then out=out..'|'; end
    return out
end


function EPGP_BuildAsciiTable(rowList,culWidth,header,culBord,rowBord)
	local testLine=makeTextLine(culWidth or {},culWidth,culBord)
	local sep1=string.rep('-',#testLine)
	local sep2=string.rep('=',#testLine)
	local out=sep1
	for i,row in ipairs(rowList) do
		out=out..nl..(makeTextLine(row,culWidth,culBord))
		if i==1 and header then
			out=out..nl..sep2
		elseif rowBord and i%rowBord == 0 then
			out=out..nl..sep1
		end
	end
	out=out..nl..sep1
	return out
end

function EPGP_BuildHtmlTable(rowList,txtColor,bgColor,borderColor,header,culBord,rowBord)
	local TableTag='<TABLE cellpadding="10" style="color: $TXTCOLOR;" bgcolor="$BGCOLOR" border="$BORDERWIDTH" bordercolor="$BORDERCOLOR" rules="$BORDERRULE" frame="box">'
	local borderW = '2'
	local borderRule = 'all'
	if culBord and rowBord then
	elseif culBord and header then borderRule='groups'
	elseif culBord then borderRule='cols'
	elseif rowBord then borderRule='rows'
	else borderW='0'
	end
	TableTag=string.gsub(TableTag,"$TXTCOLOR",txtColor)
	TableTag=string.gsub(TableTag,"$BGCOLOR",bgColor)
	TableTag=string.gsub(TableTag,"$BORDERCOLOR",borderColor)
	TableTag=string.gsub(TableTag,"$BORDERRULE",borderRule)
	TableTag=string.gsub(TableTag,"$BORDERWIDTH",borderW)
	local out=TableTag..nl
	if borderRule=='groups' then
		for i=1,#rowList[1] do
			out=out..'<COLGROUP></COLGROUP>'
		end
		out=out..nl
	end
	for i,row in ipairs(rowList) do
		local cellTag='<TD>'
		local cellTagEnd='</TD>'
		local theadStop=''
		if i==1 and header then
			cellTag='<TH>'
			cellTagEnd='</TH>'
			out=out..'<THEAD>'
			theadStop='</THEAD>'
		end
		local rowTag='<TR align="center">'
		if row.color then
			rowTag='<TR align="center" style="color: $ROWCOLOR;">'
			rowTag=string.gsub(rowTag,"$ROWCOLOR",row.color)
		end
		out=out..rowTag..nl
		for i,cell in ipairs(row) do
			cell=DecodeItemLink(cell,'html')
			out=out..cellTag..tostring(cell)..cellTagEnd
		end
		out=out..nl..'</TR>'..theadStop..nl
	end
	out=out..'</TABLE>'..nl
	return out
end


