local addonName, ns = ...
local API = ns.API
local GITHUB_URL = "https://github.com/vattiss/know-your-rotation"
local ISSUES_URL = GITHUB_URL .. "/issues"

local editSpec
local editMode
local editProfile -- the profile whose lists are shown (not always the one in use)
local listKind = "apl"

local function bindSimpleTip(frame, title, desc)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(title, 1, 0.82, 0)
		if desc then
			GameTooltip:AddLine(desc, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function makeGoldBtn(parent, width, height, label)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width, height)
	btn:SetText(label or "")
	return btn
end

local function makeCard(parent, titleKey, x, y, width, height)
	local card = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
	card:SetSize(width, height)
	card:SetPoint("TOPLEFT", x, y)
	local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(ns.T(titleKey))
	card.title = title
	card.titleKey = titleKey
	return card
end

local function copyText(text)
	if CopyToClipboard then
		pcall(CopyToClipboard, text)
	end
	if ChatFrame_OpenChat then
		local ok = pcall(ChatFrame_OpenChat, text, DEFAULT_CHAT_FRAME)
		if ok then
			local box = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
			if box and box.HighlightText then
				pcall(box.HighlightText, box)
			end
			ns.Print(ns.T("INFO_COPIED"))
			return true
		end
	end
	local box
	if ChatEdit_ChooseBoxForSend then
		local ok, chosen = pcall(ChatEdit_ChooseBoxForSend)
		if ok then
			box = chosen
		end
	end
	box = box or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
	if not box then
		return false
	end
	if ChatEdit_ActivateChat then
		pcall(ChatEdit_ActivateChat, box)
	end
	if box.SetText then
		pcall(box.SetText, box, text)
	end
	if box.HighlightText then
		pcall(box.HighlightText, box)
	end
	if box.SetFocus then
		pcall(box.SetFocus, box)
	end
	ns.Print(ns.T("INFO_COPIED"))
	return true
end

local function makeLinkRow(parent, labelKey, url)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(26)
	local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", 0, 0)
	label:SetWidth(90)
	label:SetJustifyH("LEFT")
	label:SetTextColor(0.92, 0.92, 0.92)
	label:SetText(ns.T(labelKey))
	row.label = label
	row.labelKey = labelKey
	local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
	box:SetPoint("LEFT", label, "RIGHT", 8, 0)
	box:SetPoint("RIGHT", -72, 0)
	box:SetHeight(22)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontSmall")
	box:SetTextInsets(6, 6, 2, 2)
	box:SetText(url)
	box:SetCursorPosition(0)
	if box.SetBackdrop then
		box:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 8,
			edgeSize = 8,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		box:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
		box:SetBackdropBorderColor(0.42, 0.42, 0.42, 1)
	end
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	row.box = box
	local copy = makeGoldBtn(row, 64, 22, ns.T("INFO_COPY"))
	copy:SetPoint("RIGHT", 0, 0)
	copy:SetScript("OnClick", function()
		if not copyText(url) then
			box:SetFocus()
			box:HighlightText()
		end
	end)
	row.copy = copy
	return row
end

local function modeLabel(mode)
	return ns.T("MODE_" .. (mode or "single"):upper())
end

local function specLabel(spec)
	if spec == "cat" then
		return ns.T("SPEC_CAT")
	end
	if spec == "bear" then
		return ns.T("SPEC_BEAR")
	end
	if spec == "damage" and ns.ClassToken and ns.ClassToken() == "DRUID" then
		return ns.T("SPEC_CASTER")
	end
	return ns.T("ROLE_" .. spec:upper()) or spec
end

local function ensureOptions()
	if ns.UI.options then
		return ns.UI.options
	end
	ns.optSerial = (ns.optSerial or 0) + 1
	-- One shared page host. Each Settings category (General, Rotation, ...)
	-- owns an empty panel; opening it moves this frame into that panel.
	local frame = CreateFrame("Frame", "KnowYourRotationOptions" .. ns.optSerial, UIParent)
	frame:Hide()

	local content = CreateFrame("Frame", nil, frame)
	content:SetAllPoints(frame)

	local pageTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	pageTitle:SetPoint("TOPLEFT", 16, -12)
	pageTitle:SetTextColor(1, 0.82, 0.2)
	frame.pageTitle = pageTitle

	local PAGE_TOP = -44
	local function newPage(hidden)
		local page = CreateFrame("Frame", nil, content)
		page:SetPoint("TOPLEFT", 8, PAGE_TOP)
		page:SetPoint("BOTTOMRIGHT", -8, 8)
		if hidden then
			page:Hide()
		end
		return page
	end
	local rotation = newPage(false)
	local profiles = newPage(true)

	-- Resets the lists of the profile in use, so it belongs next to the profiles.
	local resetAll = makeGoldBtn(profiles, 150, 22, ns.T("OPT_RESET_ALL"))
	resetAll:SetPoint("TOPRIGHT", profiles, "TOPRIGHT", -8, -4)
	resetAll:SetScript("OnClick", function()
		ns.ConfirmResetAll()
	end)
	frame.resetAll = resetAll

	frame.rotation = rotation
	frame.profiles = profiles
	frame.content = content

	-- List editor (Rotation and Defense pages): pick one list, then edit it.
	local editLabel = rotation:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	editLabel:SetPoint("TOPLEFT", 8, -12)
	frame.editLabel = editLabel

	local profileDrop = CreateFrame("DropdownButton", nil, rotation, "WowStyle1DropdownTemplate")
	profileDrop:SetPoint("TOPLEFT", 8, -36)
	profileDrop:SetWidth(90)
	profileDrop:SetupMenu(function(_, root)
		for _, key in ipairs(ns.PROFILE_ORDER) do
			root:CreateRadio(ns.T("PROFILE_" .. key:upper()), function(value)
				return editProfile == value
			end, function(value)
				editProfile = value
				ns.RefreshOptions()
			end, key)
		end
	end)
	frame.profileDrop = profileDrop

	local specDrop = CreateFrame("DropdownButton", nil, rotation, "WowStyle1DropdownTemplate")
	specDrop:SetPoint("LEFT", profileDrop, "RIGHT", 8, 0)
	specDrop:SetWidth(150)
	specDrop:SetupMenu(function(_, root)
		for _, spec in ipairs(ns.SpecList()) do
			root:CreateRadio(specLabel(spec), function(value)
				return editSpec == value
			end, function(value)
				editSpec = value
				ns.RefreshOptions()
			end, spec)
		end
	end)
	frame.specDrop = specDrop

	local modeDrop = CreateFrame("DropdownButton", nil, rotation, "WowStyle1DropdownTemplate")
	modeDrop:SetPoint("LEFT", specDrop, "RIGHT", 8, 0)
	modeDrop:SetWidth(120)
	modeDrop:SetupMenu(function(_, root)
		for _, mode in ipairs({ "auto", "single", "aoe" }) do
			root:CreateRadio(modeLabel(mode), function(value)
				return editMode == value
			end, function(value)
				editMode = value
				ns.RefreshOptions()
			end, mode)
		end
	end)
	frame.modeDrop = modeDrop

	local resetApl = makeGoldBtn(rotation, 110, 22, ns.T("OPT_RESET_APL"))
	resetApl:SetPoint("TOPRIGHT", -8, -8)
	-- The title runs up to the button and no further.
	editLabel:SetPoint("TOPRIGHT", resetApl, "TOPLEFT", -8, 0)
	editLabel:SetJustifyH("LEFT")
	resetApl:SetScript("OnClick", function()
		if listKind == "def" then
			ns.WithProfile(editProfile, ns.ResetDef, nil, editSpec)
		else
			ns.WithProfile(editProfile, ns.ResetAPL, nil, editSpec, editMode)
		end
		ns.RefreshOptions()
	end)
	bindSimpleTip(resetApl, ns.T("OPT_RESET_APL"), ns.T("OPT_RESET_APL_TIP"))
	frame.resetApl = resetApl

	local holdToggle = CreateFrame("CheckButton", nil, rotation, "UICheckButtonTemplate")
	holdToggle:SetSize(24, 24)
	holdToggle:SetPoint("TOPLEFT", 4, -66)
	holdToggle:SetScript("OnClick", function(self)
		ns.db.showHoldColumn = self:GetChecked() and true or nil
		ns.RefreshOptions()
	end)
	bindSimpleTip(holdToggle, ns.T("OPT_HOLD"), ns.T("OPT_HOLD_TIP"))
	frame.holdToggle = holdToggle
	local holdLabel = rotation:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	holdLabel:SetPoint("LEFT", holdToggle, "RIGHT", 2, 0)
	holdLabel:SetText(ns.T("OPT_SHOW_HOLD"))
	frame.holdLabel = holdLabel

	local listHint = rotation:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	listHint:SetPoint("LEFT", holdLabel, "RIGHT", 16, 0)
	listHint:SetPoint("RIGHT", rotation, "RIGHT", -8, 0)
	listHint:SetJustifyH("LEFT")
	frame.listHint = listHint

	local listInset = CreateFrame("Frame", nil, rotation, "InsetFrameTemplate")
	listInset:SetPoint("TOPLEFT", 4, -94)
	listInset:SetPoint("BOTTOMRIGHT", -4, 4)

	local scroll = CreateFrame("ScrollFrame", "KnowYourRotationAPLScroll", listInset, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(600, 10)
	scroll:SetScrollChild(child)
	frame.aplScroll = scroll
	frame.aplChild = child
	frame.aplRows = {}

	-- Drop target at the end of the list: drag a spell from the spellbook here.
	local addSpell = makeGoldBtn(child, 560, 26, ns.T("OPT_ADD_SPELL"))
	addSpell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	addSpell:SetScript("OnReceiveDrag", function()
		ns.DropSpellOnList(nil, listKind ~= "def" and editMode or nil)
	end)
	addSpell:SetScript("OnClick", function()
		if ns.API.CursorSpell and ns.API.CursorSpell() then
			ns.DropSpellOnList(nil, listKind ~= "def" and editMode or nil)
		end
	end)
	bindSimpleTip(addSpell, ns.T("OPT_ADD_SPELL"), ns.T("OPT_DROP_SPELL"))
	frame.addSpell = addSpell

	local shareCard = makeCard(profiles, "OPT_CARD_SHARE", 8, -36, 648, 248)
	local shareHint = shareCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	shareHint:SetPoint("TOPLEFT", 12, -28)
	shareHint:SetPoint("RIGHT", -12, 0)
	shareHint:SetJustifyH("LEFT")
	shareHint:SetTextColor(0.72, 0.72, 0.72)
	frame.shareHint = shareHint

	local box = CreateFrame("ScrollFrame", "KnowYourRotationShareScroll", shareCard, "UIPanelScrollFrameTemplate")
	box:SetPoint("TOPLEFT", 12, -50)
	box:SetPoint("BOTTOMRIGHT", -32, 40)
	local edit = CreateFrame("EditBox", "KnowYourRotationShareEdit", box)
	edit:SetMultiLine(true)
	edit:SetFontObject("ChatFontSmall")
	edit:SetWidth(580)
	edit:SetHeight(400)
	edit:SetAutoFocus(false)
	edit:EnableMouse(true)
	edit:SetMaxLetters(25000)
	edit:SetTextInsets(4, 4, 4, 4)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScrollChild(edit)
	frame.shareEdit = edit

	local exportBtn = makeGoldBtn(shareCard, 140, 22, ns.T("OPT_EXPORT"))
	exportBtn:SetPoint("BOTTOMLEFT", 12, 10)
	exportBtn:SetScript("OnClick", function()
		if ns.ExportProfile then
			edit:SetText(ns.ExportProfile())
			edit:HighlightText()
			edit:SetFocus()
		end
	end)
	frame.exportBtn = exportBtn

	local importBtn = makeGoldBtn(shareCard, 140, 22, ns.T("OPT_IMPORT"))
	importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
	importBtn:SetScript("OnClick", function()
		if not ns.ImportProfile then
			return
		end
		local ok, msg, extraArg = ns.ImportProfile(edit:GetText() or "")
		if ok then
			ns.Print(ns.T(msg))
			ns.RefreshOptions()
			return
		end
		if msg == "OPT_IMPORT_CLASS" then
			ns.Print(ns.T("OPT_IMPORT_CLASS"):format(extraArg or "?"))
			return
		end
		ns.Print(ns.T(msg or "OPT_IMPORT_BAD"))
	end)
	frame.importBtn = importBtn

	local debugBtn = makeGoldBtn(shareCard, 140, 22, ns.T("OPT_DEBUG_REPORT"))
	debugBtn:SetPoint("LEFT", importBtn, "RIGHT", 24, 0)
	debugBtn:SetScript("OnClick", function()
		edit:SetText(ns.Debug.Report())
		edit:HighlightText()
		edit:SetFocus()
	end)
	frame.debugBtn = debugBtn

	local clearBtn = makeGoldBtn(shareCard, 140, 22, ns.T("OPT_DEBUG_CLEAR"))
	clearBtn:SetPoint("LEFT", debugBtn, "RIGHT", 8, 0)
	clearBtn:SetScript("OnClick", function()
		ns.Debug.Clear()
		ns.Print(ns.T("OPT_DEBUG_CLEARED"))
	end)
	frame.clearBtn = clearBtn

	function frame.RelocalizeChrome()
		if frame.shareHint then
			frame.shareHint:SetText(ns.T("OPT_EXPORT_HINT"))
		end
		if frame.resetAll then
			frame.resetAll:SetText(ns.T("OPT_RESET_ALL"))
		end
		if frame.resetApl then
			frame.resetApl:SetText(ns.T("OPT_RESET_APL"))
		end
		if frame.exportBtn then
			frame.exportBtn:SetText(ns.T("OPT_EXPORT"))
		end
		if frame.importBtn then
			frame.importBtn:SetText(ns.T("OPT_IMPORT"))
		end
		frame.debugBtn:SetText(ns.T("OPT_DEBUG_REPORT"))
		frame.clearBtn:SetText(ns.T("OPT_DEBUG_CLEAR"))
		for _, card in ipairs({ shareCard }) do
			if card and card.title and card.titleKey then
				card.title:SetText(ns.T(card.titleKey))
			end
		end
	end

	function frame.ShowTab(which)
		frame.activeTab = which
		listKind = which == "def" and "def" or "apl"
		rotation:SetShown(which == "rotation" or which == "def")
		profiles:SetShown(which == "profiles")
		local titles = {
			rotation = "TAB_ROTATION",
			def = "TAB_DEFENSE",
			profiles = "TAB_PROFILES",
		}
		frame.pageTitle:SetText(ns.T(titles[which] or "TAB_ROTATION"))
	end

	frame.RelocalizeChrome()
	frame.ShowTab("rotation")
	ns.UI.options = frame
	return frame
end

local function aplRow(parent, index)
	local rows = ns.UI.options.aplRows
	if rows[index] then
		return rows[index]
	end
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(580, 26)
	row:EnableMouse(true)
	row:SetScript("OnReceiveDrag", function(self)
		ns.DropSpellOnList(self.index, self.mode)
	end)
	row:SetScript("OnMouseUp", function(self)
		if ns.API.CursorSpell and ns.API.CursorSpell() then
			ns.DropSpellOnList(self.index, self.mode)
		end
	end)
	row:SetScript("OnEnter", function(self)
		if not self.stepId then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.label:GetText() or "", 1, 0.82, 0)
		local text, r, g, b
		if not API.Known(self.stepId) then
			text, r, g, b = ns.T("WHY_NOT_KNOWN"), 0.7, 0.7, 0.7
		elseif not self.stepOn then
			text, r, g, b = ns.T("WHY_SWITCHED_OFF"), 0.7, 0.7, 0.7
		else
			local why = API.WhyNot and API.WhyNot(self.stepId, self.stepOpt)
			if why then
				text, r, g, b = ns.T("WHY_NOT_NOW"):format(why), 1, 0.6, 0.2
			else
				text, r, g, b = ns.T("WHY_READY"), 0.3, 1, 0.3
			end
		end
		GameTooltip:AddLine(text, r, g, b, true)
		GameTooltip:AddLine(ns.T("WHY_HINT"), 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local num = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	num:SetPoint("LEFT", 2, 0)
	num:SetWidth(18)
	row.num = num

	local box = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	box:SetPoint("LEFT", 20, 0)
	box:SetSize(24, 24)
	row.box = box

	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("LEFT", 48, 0)
	row.icon = icon

	local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	name:SetPoint("LEFT", 74, 0)
	name:SetWidth(240)
	name:SetJustifyH("LEFT")
	row.label = name

	local del = makeGoldBtn(row, 64, 20, ns.T("OPT_REMOVE_SPELL"))
	del:SetPoint("RIGHT", 0, 0)
	bindSimpleTip(del, ns.T("OPT_REMOVE_SPELL"), ns.T("OPT_REMOVE_SPELL_TIP"))
	row.del = del

	local down = makeGoldBtn(row, 52, 20, ns.T("OPT_MOVE_DOWN"))
	down:SetPoint("RIGHT", del, "LEFT", -4, 0)
	bindSimpleTip(down, ns.T("OPT_MOVE_DOWN"), ns.T("OPT_MOVE_DOWN_TIP"))
	row.down = down

	local up = makeGoldBtn(row, 44, 20, ns.T("OPT_MOVE_UP"))
	up:SetPoint("RIGHT", down, "LEFT", -4, 0)
	bindSimpleTip(up, ns.T("OPT_MOVE_UP"), ns.T("OPT_MOVE_UP_TIP"))
	row.up = up

	-- Optional "delay" column (Show delay column switch above the list).
	local hold = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	hold:SetSize(30, 18)
	hold:SetPoint("RIGHT", up, "LEFT", -18, 0)
	hold:SetAutoFocus(false)
	hold:SetNumeric(true)
	hold:SetMaxLetters(3)
	hold:SetJustifyH("CENTER")
	row.hold = hold
	local holdUnit = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	holdUnit:SetPoint("LEFT", hold, "RIGHT", 2, 0)
	holdUnit:SetText("s")
	row.holdUnit = holdUnit

	local function commitHold(self)
		if not self.stepKey then
			return
		end
		local sec = tonumber(self:GetText()) or 0
		if listKind == "def" then
			ns.WithProfile(editProfile, ns.SetDefHold, self.stepKey, sec, nil, editSpec)
		else
			ns.WithProfile(editProfile, ns.SetAPLHold, self.stepKey, sec, nil, editSpec, self.mode)
		end
		ns.RefreshOptions()
	end
	hold:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		commitHold(self)
	end)
	hold:SetScript("OnEditFocusLost", commitHold)
	hold:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		ns.RefreshOptions()
	end)
	bindSimpleTip(hold, ns.T("OPT_HOLD"), ns.T("OPT_HOLD_TIP"))

	box:SetScript("OnClick", function(self)
		if self.stepKey then
			local on = ns.CoerceChecked(self:GetChecked())
			if listKind == "def" then
				ns.WithProfile(editProfile, ns.SetDefEnabled, self.stepKey, on, nil, editSpec)
			else
				ns.WithProfile(editProfile, ns.SetAPLEnabled, self.stepKey, on, nil, editSpec, self.mode)
			end
			ns.RefreshOptions()
		end
	end)
	up:SetScript("OnClick", function(self)
		if self.index then
			if listKind == "def" then
				ns.WithProfile(editProfile, ns.MoveDef, self.index, -1, nil, editSpec)
			else
				ns.WithProfile(editProfile, ns.MoveAPL, self.index, -1, nil, editSpec, self.mode)
			end
			ns.RefreshOptions()
		end
	end)
	down:SetScript("OnClick", function(self)
		if self.index then
			if listKind == "def" then
				ns.WithProfile(editProfile, ns.MoveDef, self.index, 1, nil, editSpec)
			else
				ns.WithProfile(editProfile, ns.MoveAPL, self.index, 1, nil, editSpec, self.mode)
			end
			ns.RefreshOptions()
		end
	end)
	del:SetScript("OnClick", function(self)
		if not self.stepKey then
			return
		end
		if listKind == "def" then
			ns.WithProfile(editProfile, ns.RemoveDef, self.stepKey, nil, editSpec)
		else
			ns.WithProfile(editProfile, ns.RemoveAPL, self.stepKey, nil, editSpec, self.mode)
		end
		ns.RefreshOptions()
	end)

	rows[index] = row
	return row
end

function ns.DropSpellOnList(atIndex, mode)
	local spellID = ns.API.CursorSpell and ns.API.CursorSpell()
	if not spellID then
		return
	end
	if listKind == "def" or (ns.IsMaintenanceBuff and ns.IsMaintenanceBuff(spellID)) then
		ns.WithProfile(editProfile, ns.AddDef, spellID, nil, editSpec, atIndex)
	else
		ns.WithProfile(editProfile, ns.AddAPL, spellID, nil, editSpec, mode or editMode, atIndex)
	end
	if ClearCursor then
		pcall(ClearCursor)
	end
	ns.RefreshOptions()
end

function ns.RefreshOptions()
	-- Nothing to refresh until the Settings panel is open; it rebuilds on show.
	if not ns.optionsWarm and not (ns.UI.options and ns.UI.options:IsVisible()) then
		return
	end
	local frame = ensureOptions()
	if frame.RelocalizeChrome then
		pcall(frame.RelocalizeChrome)
	end
	if frame.ShowTab and frame.activeTab then
		frame.ShowTab(frame.activeTab)
	end
	editSpec = editSpec or ns.ActiveSpec()
	editProfile = editProfile or ns.ProfileKey()
	editMode = editMode or (ns.CombatMode and ns.CombatMode()) or "auto"
	if editMode ~= "auto" and editMode ~= "aoe" then
		editMode = "single"
	end
	local specs = ns.SpecList()
	local valid = false
	for _, spec in ipairs(specs) do
		if spec == editSpec then
			valid = true
		end
	end
	if not valid then
		editSpec = specs[1]
	end
	local profile = ns.T("PROFILE_" .. editProfile:upper())
	local label = ns.T(listKind == "def" and "EDIT_DEF_FOR" or "EDIT_ROT_FOR"):format(profile)
	local activeSpec = ns.ActiveSpec and ns.ActiveSpec()
	local activeMode = ns.ResolveCombatMode and ns.ResolveCombatMode() or "auto"
	if editProfile == ns.ProfileKey() and editSpec == activeSpec and (listKind == "def" or editMode == activeMode) then
		label = label .. "  |cff33ff33" .. ns.T("EDIT_IN_USE") .. "|r"
	end
	frame.editLabel:SetText(label)
	frame.specDrop:GenerateMenu()
	frame.profileDrop:GenerateMenu()
	frame.modeDrop:SetShown(listKind ~= "def")
	if listKind ~= "def" then
		frame.modeDrop:GenerateMenu()
	end
	frame.holdToggle:SetChecked(ns.db.showHoldColumn == true)
	if editProfile ~= ns.ProfileKey() then
		frame.listHint:SetText(
			ns.T("EDIT_PROFILE")
				:format(ns.T("PROFILE_" .. editProfile:upper()), ns.T("PROFILE_" .. ns.ProfileKey():upper()))
		)
	elseif listKind ~= "def" and editMode == "auto" then
		frame.listHint:SetText(ns.T("OPT_AUTO_HINT"))
	else
		frame.listHint:SetText(ns.T("OPT_LIST_HINT"))
	end
	-- The spell list is the slow part: only rebuild it on the pages that show it.
	if frame.activeTab ~= "rotation" and frame.activeTab ~= "def" then
		return
	end
	local child = frame.aplChild
	local showHold = ns.db.showHoldColumn == true
	local mode = listKind ~= "def" and editMode or nil
	local steps
	if listKind == "def" then
		steps = ns.WithProfile(editProfile, ns.GetDef, nil, editSpec)
	else
		steps = ns.WithProfile(editProfile, ns.GetAPL, nil, editSpec, editMode)
	end
	local y = 2
	for i, step in ipairs(steps) do
		local row = aplRow(child, i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -y)
		row:Show()
		row.mode = mode
		row.index = i
		row.num:SetText(tostring(i))
		row.box.stepKey = step.key
		row.box.mode = mode
		row.box:SetChecked(ns.IsStepEnabled(step))
		row.stepId = step.id
		row.stepOpt = step.opt
		row.stepOn = ns.IsStepEnabled(step)
		row.up.index = i
		row.up.mode = mode
		row.down.index = i
		row.down.mode = mode
		row.del.stepKey = step.key
		row.del.mode = mode
		row.icon:SetTexture(API.SpellIcon(step.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
		local name = API.SpellLabel(step.id) or step.key
		if step.racial then
			name = ns.T("RACIAL_PREFIX"):format(name)
		end
		row.label:SetText(name)
		local known = API.Known(step.id)
		local shade = known and 1 or 0.55
		row.label:SetTextColor(shade, shade, shade)
		row.hold:SetShown(showHold)
		row.holdUnit:SetShown(showHold)
		row.hold.stepKey = step.key
		row.hold.mode = mode
		if showHold and not row.hold:HasFocus() then
			local hold = step.opt and tonumber(step.opt.hold)
			if hold == nil and ns.SPELL_HOLD and step.id then
				hold = ns.SPELL_HOLD[step.id]
			end
			row.hold:SetText(tostring(hold or 0))
		end
		y = y + 28
	end
	for i = #steps + 1, #frame.aplRows do
		local row = frame.aplRows[i]
		row:Hide()
		row.index = nil
		row.mode = nil
		row.box.stepKey = nil
		row.stepId = nil
		row.del.stepKey = nil
		row.hold.stepKey = nil
	end
	frame.addSpell:ClearAllPoints()
	frame.addSpell:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -(y + 4))
	frame.addSpell:Show()
	child:SetHeight(math.max(40, y + 40))
end

-- The options live in the game's Settings window, under AddOns: one category
-- for a landing page, with one sub-category (expandable with +) per page.
local TABS = {
	{ "rotation", "TAB_ROTATION" },
	{ "def", "TAB_DEFENSE" },
	{ "profiles", "TAB_PROFILES" },
}

-- Build the heavy page host a few seconds after login, out of combat, so the
-- first click in the Settings window does not stall.
function ns.PrebuildOptions()
	if ns.UI.options then
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		return
	end
	pcall(ensureOptions)
	-- A little later, create the spell-list rows once while hidden.
	if C_Timer and C_Timer.After then
		C_Timer.After(2, ns.WarmOptionsList)
	end
end

function ns.WarmOptionsList()
	local frame = ns.UI.options
	if not frame or frame:IsVisible() or (InCombatLockdown and InCombatLockdown()) then
		return
	end
	local previous = frame.activeTab
	ns.optionsWarm = true
	frame.activeTab = "rotation"
	pcall(ns.RefreshOptions)
	frame.activeTab = previous
	ns.optionsWarm = false
end

-- Native Settings pages (Highlights, Behavior): Blizzard checkboxes, dropdowns,
-- sliders and color swatches. Proxy settings read and write ns.db directly.
local function afterChange()
	if ns.FlushProfile then
		ns.FlushProfile()
	end
	if ns.InvalidateAPLCache then
		ns.InvalidateAPLCache()
	end
	if ns.ApplyFeatureFlags then
		ns.ApplyFeatureFlags()
	elseif ns.Tick then
		ns.Tick()
	end
end

local function proxy(category, variable, varType, labelKey, default, get, set)
	return Settings.RegisterProxySetting(
		category,
		"KnowYourRotation_" .. variable,
		varType,
		ns.T(labelKey),
		default,
		get,
		set
	)
end

local function header(layout, labelKey)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(ns.T(labelKey)))
end

local function checkbox(category, variable, labelKey, tipKey, default, get, set)
	local setting = proxy(category, variable, Settings.VarType.Boolean, labelKey, default, get, set)
	Settings.CreateCheckbox(category, setting, tipKey and ns.T(tipKey) or nil)
end

-- A switch stored as ns.db[key], on unless set to false.
local function featureCheckbox(category, key, labelKey, tipKey)
	checkbox(category, key, labelKey, tipKey, true, function()
		return ns.db[key] ~= false
	end, function(value)
		ns.db[key] = value and true or false
		afterChange()
	end)
end

-- items() returns { { value, label }, ... }
local function dropdown(category, variable, labelKey, tipKey, default, get, set, items)
	local setting = proxy(category, variable, Settings.VarType.String, labelKey, default, get, set)
	local function options()
		local container = Settings.CreateControlTextContainer()
		for _, item in ipairs(items()) do
			container:Add(item[1], item[2])
		end
		return container:GetData()
	end
	Settings.CreateDropdown(category, setting, options, tipKey and ns.T(tipKey) or nil)
end

local function soundDropdown(category, dbKey, labelKey)
	dropdown(category, dbKey, labelKey, "TIP_SOUND", ns.db[dbKey] or "none", function()
		return ns.db[dbKey] or "none"
	end, function(value)
		ns.db[dbKey] = value
		ns.PlayAlertSound(value)
	end, function()
		local list = {}
		for _, entry in ipairs(ns.SOUNDS or {}) do
			list[#list + 1] = { entry.key, ns.T(entry.label) }
		end
		return list
	end)
end

local function colorSwatch(category, key, labelKey)
	if not Settings.CreateColorSwatch or not CreateColor or not CreateColorFromHexString then
		return
	end
	local d = ns.COLOR_DEFAULTS[key] or ns.COLOR_DEFAULTS.next
	local default = CreateColor(d[1], d[2], d[3]):GenerateHexColor()
	local setting = proxy(category, "color_" .. key, Settings.VarType.String, labelKey, default, function()
		local r, g, b = ns.Color(key)
		return CreateColor(r, g, b):GenerateHexColor()
	end, function(value)
		local color = CreateColorFromHexString(value)
		if color then
			ns.db.colors = ns.db.colors or {}
			ns.db.colors[key] = { color.r, color.g, color.b }
			if ns.GlowInvalidate then
				ns.GlowInvalidate()
			end
			afterChange()
		end
	end)
	Settings.CreateColorSwatch(category, setting, nil)
end

local function registerHighlights(root)
	local category, layout = Settings.RegisterVerticalLayoutSubcategory(root, ns.T("TAB_HIGHLIGHTS"))
	local token = ns.ClassToken and ns.ClassToken()

	header(layout, "HDR_CHARACTER")
	checkbox(category, "muted", "OPT_MUTE", "TIP_MUTE", false, function()
		return ns.db.muted == true
	end, function(value)
		ns.db.muted = value and true or nil
		afterChange()
	end)

	header(layout, "HDR_ROTATION")
	featureCheckbox(category, "showRotation", "OPT_ROTATION", "TIP_ROTATION")
	colorSwatch(category, "next", "OPT_COLOR_NEXT")
	colorSwatch(category, "heal", "OPT_COLOR_HEAL")
	if token == "HUNTER" then
		colorSwatch(category, "shot", "OPT_COLOR_SHOT")
	end

	header(layout, "HDR_DEFENSE")
	featureCheckbox(category, "showDefense", "OPT_DEFENSE", "TIP_DEFENSE")
	colorSwatch(category, "def", "OPT_COLOR_DEF")

	-- Only the cues this class can use.
	if token and ns.INTERRUPTS and ns.INTERRUPTS[token] then
		header(layout, "HDR_INTERRUPT")
		featureCheckbox(category, "showInterrupt", "OPT_INTERRUPT", "TIP_INTERRUPT")
		soundDropdown(category, "soundKick", "OPT_SOUND")
	end
	if token and ns.PURGES and ns.PURGES[token] then
		header(layout, "HDR_PURGE")
		featureCheckbox(category, "showPurge", "OPT_PURGE", "TIP_PURGE")
	end
	if token and ns.CLEANSE and ns.CLEANSE[token] then
		header(layout, "HDR_CLEANSE")
		featureCheckbox(category, "showCleanse", "OPT_CLEANSE", "TIP_CLEANSE")
		featureCheckbox(category, "cleanseGroup", "OPT_CLEANSE_GROUP", nil)
		soundDropdown(category, "soundCleanse", "OPT_SOUND")
	end
	if token == "SHAMAN" then
		header(layout, "HDR_TOTEM")
		featureCheckbox(category, "showTotem", "OPT_TOTEM", "TIP_TOTEM")
		colorSwatch(category, "totem", "OPT_COLOR_TOTEM")
	end
	local choices = ns.WeaponChoices and ns.WeaponChoices() or {}
	if #choices > 0 then
		header(layout, "HDR_WEAPON")
		featureCheckbox(category, "showWeapon", "OPT_WEAPON", "TIP_WEAPON")
		-- One pick, or one per hand for classes that coat both weapons.
		local function weaponPick(variable, dbKey, labelKey, offhand)
			dropdown(category, variable, labelKey, "TIP_WEAPON_PICK", "auto", function()
				local key = ns.db[dbKey]
				for _, entry in ipairs(ns.WeaponChoices() or {}) do
					if entry.key == key and ns.WeaponBuffLearned(entry) then
						return key
					end
				end
				return "auto"
			end, function(value)
				ns.db[dbKey] = value ~= "auto" and value or nil
				afterChange()
			end, function()
				local auto = ns.AutoWeaponBuff(offhand)
				local label = ns.T("OPT_AUTOMATIC")
				if auto then
					label = label .. " (" .. (API.SpellLabel(auto.id) or auto.key) .. ")"
				end
				local list = { { "auto", label } }
				for _, entry in ipairs(ns.WeaponChoices() or {}) do
					if ns.WeaponBuffLearned(entry) then
						list[#list + 1] = { entry.key, API.SpellLabel(entry.id) or entry.key }
					end
				end
				return list
			end)
		end
		if ns.WeaponHasOffhandChoice() then
			weaponPick("weaponBuff", "weaponBuff", "OPT_WEAPON_PICK_MAIN", false)
			weaponPick("weaponBuffOff", "weaponBuffOff", "OPT_WEAPON_PICK_OFF", true)
		else
			weaponPick("weaponBuff", "weaponBuff", "OPT_WEAPON_PICK", false)
		end
		soundDropdown(category, "soundWeapon", "OPT_SOUND")
		colorSwatch(category, "weapon", "OPT_COLOR_WEAPON")
	end
end

local function registerBehavior(root)
	local category, layout = Settings.RegisterVerticalLayoutSubcategory(root, ns.T("TAB_BEHAVIOR"))

	header(layout, "HDR_DETECTION")
	dropdown(category, "profile", "OPT_PROFILE", "TIP_PROFILE", "auto", function()
		return ns.ProfileChoice()
	end, function(value)
		ns.SetProfileChoice(value)
	end, function()
		return {
			{ "auto", ns.T("OPT_AUTOMATIC") },
			{ "pve", ns.T("PROFILE_PVE") },
			{ "pvp", ns.T("PROFILE_PVP") },
		}
	end)
	dropdown(category, "role", "OPT_ROLE", "TIP_ROLE", "auto", function()
		return ns.RoleChoice()
	end, function(value)
		ns.SetRoleChoice(value)
	end, function()
		local list = { { "auto", ns.T("OPT_AUTOMATIC") } }
		local token = ns.ClassToken and ns.ClassToken()
		for _, role in ipairs(token and ns.CLASS_ROLES[token] or { "damage" }) do
			list[#list + 1] = { role, ns.T("ROLE_" .. role:upper()) }
		end
		return list
	end)
	dropdown(category, "combatMode", "OPT_COMBAT_MODE", "TIP_COMBAT_MODE", "auto", function()
		return ns.CombatMode()
	end, function(value)
		ns.SetCombatMode(value)
	end, function()
		return {
			{ "auto", ns.T("OPT_AUTOMATIC") },
			{ "single", ns.T("MODE_SINGLE") },
			{ "aoe", ns.T("MODE_AOE") },
		}
	end)
	local aoe = proxy(category, "autoEnemies", Settings.VarType.Number, "OPT_AOE_FROM", 3, function()
		return tonumber(ns.db.autoEnemies) or 3
	end, function(value)
		ns.db.autoEnemies = math.floor((tonumber(value) or 3) + 0.5)
		afterChange()
	end)
	local sliderOptions = Settings.CreateSliderOptions(2, 8, 1)
	if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
		sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return string.format("%d", value)
		end)
	end
	Settings.CreateSlider(category, aoe, sliderOptions, ns.T("TIP_AOE_FROM"))

	header(layout, "HDR_SUGGESTIONS")
	featureCheckbox(category, "autoHeal", "OPT_AUTO_HEAL", "TIP_AUTO_HEAL")
	featureCheckbox(category, "showPhysics", "OPT_PHYSICS", "TIP_PHYSICS")

	header(layout, "HDR_DEBUG")
	checkbox(category, "debugMode", "OPT_DEBUG", "TIP_DEBUG", false, function()
		return ns.db.debugMode == true
	end, function(value)
		ns.db.debugMode = value and true or nil
		ns.Debug.Apply()
	end)
end

function ns.RegisterOptions()
	if ns.optionsCategory or not Settings or not Settings.RegisterCanvasLayoutCategory then
		return
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(4, ns.PrebuildOptions)
	end
	-- Main entry: a short landing page. The real pages are its sub-categories.
	local home = CreateFrame("Frame", "KnowYourRotationPanelHome")
	local homeTitle = home:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	homeTitle:SetPoint("TOPLEFT", 16, -16)
	homeTitle:SetTextColor(1, 0.82, 0.2)
	homeTitle:SetText(ns.T("TITLE"))
	local homeName = home:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	homeName:SetPoint("TOPLEFT", homeTitle, "BOTTOMLEFT", 0, -6)
	homeName:SetText(ns.T("OPT_HOME_WELCOME"))
	local homeText = home:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	homeText:SetPoint("TOPLEFT", homeName, "BOTTOMLEFT", 0, -16)
	homeText:SetPoint("RIGHT", home, "RIGHT", -24, 0)
	homeText:SetJustifyH("LEFT")
	homeText:SetWordWrap(true)
	homeText:SetText(ns.T("OPT_HOME_TEXT"))
	local homeBeta = home:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	homeBeta:SetPoint("TOPLEFT", homeText, "BOTTOMLEFT", 0, -12)
	homeBeta:SetPoint("RIGHT", home, "RIGHT", -24, 0)
	homeBeta:SetJustifyH("LEFT")
	homeBeta:SetWordWrap(true)
	homeBeta:SetTextColor(1, 0.6, 0.2)
	homeBeta:SetText(ns.T("OPT_HOME_BETA"))
	local homeHelp = home:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	homeHelp:SetPoint("TOPLEFT", homeBeta, "BOTTOMLEFT", 0, -8)
	homeHelp:SetPoint("RIGHT", home, "RIGHT", -24, 0)
	homeHelp:SetJustifyH("LEFT")
	homeHelp:SetWordWrap(true)
	homeHelp:SetText(ns.T("OPT_HOME_HELP"))
	local homeStatus = home:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	homeStatus:SetPoint("TOPLEFT", homeHelp, "BOTTOMLEFT", 0, -20)
	homeStatus:SetPoint("RIGHT", home, "RIGHT", -24, 0)
	homeStatus:SetJustifyH("LEFT")
	homeStatus:SetWordWrap(true)
	local homeSupport = home:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	homeSupport:SetPoint("TOPLEFT", homeStatus, "BOTTOMLEFT", 0, -24)
	homeSupport:SetPoint("RIGHT", home, "RIGHT", -24, 0)
	homeSupport:SetJustifyH("LEFT")
	homeSupport:SetText(ns.T("INFO_SUPPORT"))
	local githubRow = makeLinkRow(home, "INFO_GITHUB", GITHUB_URL)
	githubRow:SetPoint("TOPLEFT", homeSupport, "BOTTOMLEFT", 0, -8)
	githubRow:SetPoint("RIGHT", home, "RIGHT", -24, 0)
	local issuesRow = makeLinkRow(home, "INFO_ISSUES", ISSUES_URL)
	issuesRow:SetPoint("TOPLEFT", githubRow, "BOTTOMLEFT", 0, -4)
	issuesRow:SetPoint("RIGHT", home, "RIGHT", -24, 0)

	-- "Right now: Shaman · Caster (automatic) · Single (automatic) · PvE (automatic)"
	local function statusText()
		local _, _, className = ns.ClassToken()
		local auto = " " .. ns.T("HOME_AUTO_SUFFIX")
		local role = ns.T("ROLE_" .. tostring(ns.db.role or "damage"):upper())
		if ns.db.roleAuto ~= false then
			role = role .. auto
		end
		local mode = ns.CombatMode()
		local modeText
		if mode == "auto" then
			local now = ns.ResolveCombatMode and ns.ResolveCombatMode() or "single"
			modeText = ns.T(now == "aoe" and "MODE_AOE" or "MODE_SINGLE") .. auto
		else
			modeText = ns.T(mode == "aoe" and "MODE_AOE" or "MODE_SINGLE")
		end
		local profile = ns.T("PROFILE_" .. ns.ProfileKey():upper())
		if ns.db.autoProfile ~= false then
			profile = profile .. auto
		end
		local line = ns.T("HOME_STATUS"):format(className or "?", profile, role, modeText)
		if ns.db.muted == true then
			line = line .. "\n" .. ns.T("HOME_DISABLED")
		end
		return line
	end
	-- New frames start shown; hide so Settings' first Show() fires OnShow.
	home:Hide()
	home:SetScript("OnShow", function()
		pcall(function()
			homeStatus:SetText(statusText())
		end)
	end)
	local root = Settings.RegisterCanvasLayoutCategory(home, ns.T("TITLE"))
	Settings.RegisterAddOnCategory(root)
	ns.optionsCategory = root

	registerHighlights(root)
	registerBehavior(root)

	for _, tab in ipairs(TABS) do
		local key, labelKey = tab[1], tab[2]
		local panel = CreateFrame("Frame", "KnowYourRotationPanel" .. key)
		-- A new frame starts shown, so Settings' first Show() would not fire
		-- OnShow and the page stayed empty until it was opened a second time.
		panel:Hide()
		local function showPage(self)
			editSpec = ns.ActiveSpec()
			editProfile = ns.ProfileKey()
			local frame = ensureOptions()
			frame:SetParent(self)
			frame:ClearAllPoints()
			frame:SetAllPoints(self)
			frame:Show()
			frame.ShowTab(key)
			-- Settings shows its canvas after this panel, so the frame is not
			-- "visible" yet; force the refresh instead of waiting for that.
			ns.optionsWarm = true
			local ok, err = pcall(ns.RefreshOptions)
			ns.optionsWarm = false
			if not ok then
				ns.Print(tostring(err))
			end
		end
		panel:SetScript("OnShow", showPage)
		Settings.RegisterCanvasLayoutSubcategory(root, panel, ns.T(labelKey))
	end
end
