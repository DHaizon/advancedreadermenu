local Dispatcher = require("dispatcher")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Translator = require("ui/translator")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local Installer = require("advancedreadermenu_installer")
local _ = require("gettext")
require("highlight_colors")

local logprefix = "[AdvancedReaderMenu] Installer:"

-- Override editHighlight methods to pass index to our custom dialogs
function ReaderHighlight:editHighlightStyle(index)
    local item = self.ui.annotation.annotations[index]
    local apply_drawer = function(drawer)
        self:writePdfAnnotation("delete", item)
        item.drawer = drawer
        if self.ui.paging then
            self:writePdfAnnotation("save", item)
            if item.note then
                self:writePdfAnnotation("content", item, item.note)
            end
        end
        UIManager:setDirty(self.dialog, "ui")
        self.ui:handleEvent(require("ui/event"):new("AnnotationsModified", { item }))
    end
    self:showHighlightStyleDialog(apply_drawer, item.drawer, index)
end

function ReaderHighlight:editHighlightColor(index)
    local item = self.ui.annotation.annotations[index]
    local apply_color = function(color)
        self:writePdfAnnotation("delete", item)
        item.color = color
        if self.ui.paging then
            self:writePdfAnnotation("save", item)
            if item.note then
                self:writePdfAnnotation("content", item, item.note)
            end
        end
        UIManager:setDirty(self.dialog, "ui")
        self.ui:handleEvent(require("ui/event"):new("AnnotationsModified", { item }))
    end
    self:showHighlightColorDialog(apply_color, item.color, index)
end

-- Override creation of the UI for the reader highlight menu.
function ReaderHighlight:onShowHighlightMenu(index)
	local selectButton = nil
	local highlightButton = nil
	local searchButton = nil
	local wikipediaButton = nil
	local wordReferenceButton = nil
	local dictionaryButton = nil
	local assistantButton = nil
	local translateButton = nil
	local copyButton = nil
	local pinTextButton = nil
	local addNoteButton = nil
	local styleButton = nil
	local unknownButtons = {}

	for key, fn_button in ffiUtil.orderedPairs(self._highlight_buttons) do
		local button = fn_button(self, index)
		if not button.show_in_highlight_dialog_func or button.show_in_highlight_dialog_func() then
			-- Remove leading index if present.
			local key_without_index = string.match(key, "^%d+_(.*)$") or key

			if key_without_index == "select" then
				button.text = nil
				button.text_func = nil
				button.icon = index and "button.select-extend" or "button.select"
				selectButton = button
			elseif key_without_index == "highlight" then
				button.text = nil
				button.text_func = nil
				button.icon = "button.highlight"
				-- Disable button flash to prevent e-ink overlap collision with the new dialog
				button.onTapSelect = function() end
				button.onTapDeselect = function() end
				button.callback = function()
					if index then
						self:editHighlightColor(index)
						self:onClose()
					else
						if self.showHighlightColorDialog then
							local curr_color = self.selected_text and self.selected_text.color or self.view.highlight.saved_color
							self:onClose(true)
							self:showHighlightColorDialog(function(color)
								if not self.selected_text then return end
								self.view.highlight.saved_color = color
								self.selected_text.color = color
								self:saveHighlight(true)
								self:clear()
							end, curr_color)
						else
							self:saveHighlight(true)
							self:onClose()
						end
					end
				end
				highlightButton = button
			elseif key_without_index == "wikipedia" then
				button.text = nil
				button.text_func = nil
				button.icon = "button.wikipedia"
				wikipediaButton = button
			elseif key_without_index == "dictionary" then
				button.text = nil
				button.text_func = nil
				button.icon = "button.dictionary"
				dictionaryButton = button
			elseif key_without_index == "translate" then
				button.text = nil
				button.text_func = nil
				button.icon = "button.translate"
				translateButton = button
			elseif key_without_index == "wordreference" then
				button.text = nil
				button.text_func = nil
				button.icon = "button.wordreference"
				wordReferenceButton = button
			elseif key_without_index == "search" then
				button.text = nil
				button.text_func = nil
				button.icon = "button.search"
				searchButton = button
			elseif key_without_index == "ai_assistant" then
				button.text = nil
				button.text_func = nil
				button.icon = "button.assistant"
				assistantButton = button
			elseif key_without_index == "pinnedelements_pin_text" then
				button.text = nil
				button.text_func = nil
				button.icon = "button.pin"
				pinTextButton = button
			elseif key_without_index == "copy" then
				button.text = nil
				button.text_func = nil
				button.icon = "button.copy"
				copyButton = button
			elseif key_without_index == "add_note" or key_without_index == "bookmark" then
				button.text = nil
				button.text_func = nil
				button.icon = "button.add_note"
				if index then
					button.enabled = true
					button.callback = function()
						self:editNote(index)
						self:onClose()
					end
				else
					button.callback = function()
						self:addNote()
						self:onClose(true)
					end
				end
				addNoteButton = button
			elseif key_without_index == "style" then
				button.text = nil
				button.text_func = nil
				button.icon = "button.underline"
				button.callback = function()
					if index then
						self:editHighlightStyle(index)
						self:onClose()
					else
						local curr_style = self.view.highlight.saved_drawer
						self:onClose(true)
						self:showHighlightStyleDialog(function(style)
							if not self.selected_text then return end
							self.view.highlight.saved_drawer = style
							self.selected_text.drawer = style
							self:saveHighlight(true)
							self:clear()
						end, curr_style)
					end
				end
				styleButton = button
			else
				table.insert(unknownButtons, button)
			end
		end
	end

	if not styleButton then
		styleButton = {
			icon = "button.underline",
			enabled = true,
			callback = function()
				if index then
					self:editHighlightStyle(index)
					self:onClose()
				else
					local curr_style = self.view.highlight.saved_drawer
					self:onClose(true)
					self:showHighlightStyleDialog(function(style)
						if not self.selected_text then return end
						self.view.highlight.saved_drawer = style
						self.selected_text.drawer = style
						self:saveHighlight(true)
						self:clear()
					end, curr_style)
				end
			end
		}
	end

	local highlight_buttons = { {} }

	local function addPrimaryButton(btn)
		if btn ~= nil then
			table.insert(highlight_buttons[1], btn)
		end
	end

	-- Add primary buttons in desired order safely.
	addPrimaryButton(selectButton)
	addPrimaryButton(highlightButton)
	addPrimaryButton(styleButton)
	addPrimaryButton(copyButton)
	addPrimaryButton(addNoteButton)
	addPrimaryButton(pinTextButton)
	addPrimaryButton(wordReferenceButton)
	addPrimaryButton(translateButton)
	addPrimaryButton(assistantButton)

	local AdvancedReaderMenu = self.ui["zzz-advancedreadermenu"]
	if AdvancedReaderMenu:getShowUnknownButtons() then
		-- Split unknownButtons into smaller rows.
		local maxRowLength = 2
		if #unknownButtons > 0 then
			for i = 1, #unknownButtons, maxRowLength do
				local row = {}
				for j = i, math.min(i + maxRowLength - 1, #unknownButtons) do
					row[#row + 1] = unknownButtons[j]
				end
				highlight_buttons[#highlight_buttons + 1] = row
			end
		end
	end

	self.highlight_dialog = ButtonDialog:new {
		buttons = highlight_buttons,
		anchor = function()
			return self:_getDialogAnchor(self.highlight_dialog, index)
		end,
		tap_close_callback = function()
			if self.hold_pos then
				self:clear()
			end
		end,
	}

	-- NOTE: Disable merging for this update,
	--       or the buggy Sage kernel may alpha-blend it into the page (with a bogus alpha value, to boot)...
	UIManager:show(self.highlight_dialog, "[ui]")
end

-- Perform installation of resources.
if Installer:installIcons() then
	logger.warn(logprefix, "Completed installation of icons.")
else
	logger.warn(logprefix, "Failed to install icons.")
end

-- Create the instance for the AdvancedReaderMenu plugin.
local AdvancedReaderMenu = WidgetContainer:extend {
	name = "zzz-advancedreadermenu",
	is_doc_only = false,
}

function AdvancedReaderMenu:init()
	self:onDispatcherRegisterActions()
	self.ui.menu:registerToMainMenu(self)
	
	-- Initialize fancy underlines natively
	local success, err = pcall(function()
		require("fancyunderlines_logic")()
		require("highlight_styles")
	end)
	if not success then
		logger.warn("Failed to initialize fancyunderlines_logic: ", err)
	end
end

function AdvancedReaderMenu:onDispatcherRegisterActions()
	Dispatcher:registerAction("advancedreadermenu_action", { category = "none", event = "Close", title = _("Advanced Reader Menu"), general = true, })
end

function AdvancedReaderMenu:getShowUnknownButtons()
	return G_reader_settings:nilOrTrue("advancedreadermenu_show_unknown_buttons")
end

function AdvancedReaderMenu:toggleShowUnknownButtons()
	local newValue = not self:getShowUnknownButtons()
	G_reader_settings:saveSetting("advancedreadermenu_show_unknown_buttons", newValue)
end

function AdvancedReaderMenu:getShowDictionaryNavButtons()
	return G_reader_settings:isTrue("advancedreadermenu_show_dictionary_nav_buttons")
end

function AdvancedReaderMenu:toggleShowDictionaryNavButtons()
	local newValue = not self:getShowDictionaryNavButtons()
	G_reader_settings:saveSetting("advancedreadermenu_show_dictionary_nav_buttons", newValue)
end

function AdvancedReaderMenu:addToMainMenu(menu_items)
	menu_items.advancedreadermenu = {
		text = "Advanced Reader Menu",
		sorting_hint = "more_tools",
		sub_item_table = {
			{
				text = "Show Unknown Buttons In Reader Highlight Menu",
				checked_func = function()
					return self:getShowUnknownButtons()
				end,
				callback = function(button)
					self:toggleShowUnknownButtons()
				end,
			},
			{
				text = "Show Nav Buttons In Dict Quick Lookup",
				checked_func = function()
					return self:getShowDictionaryNavButtons()
				end,
				callback = function(button)
					self:toggleShowDictionaryNavButtons()
				end,
			},
		},
	}
end

function AdvancedReaderMenu:onDictButtonsReady(dict_popup, buttons)
	if dict_popup.is_wiki_fullpage then
		return false
	end

	local vocabularyButton = nil
	local prevDictButton = nil
	local nextDictButton = nil
	local highlightButton = nil
	local searchButton = nil
	local wikipediaButton = nil
	local closeButton = nil
	local wordReferenceButton = nil
	local unknownButtons = {}

	for row = 1, #buttons do
		for column = 1, #buttons[row] do
			local button = buttons[row][column]

			if button.id == "vocabulary" then
				vocabularyButton = button
			elseif button.id == "prev_dict" then
				if self:getShowDictionaryNavButtons() then
					prevDictButton = button
				end
			elseif button.id == "next_dict" then
				if self:getShowDictionaryNavButtons() then
					nextDictButton = button
				end
			elseif button.id == "highlight" then
				button.text = nil
				button.icon = "button.highlight"
				button.callback = function()
					dict_popup.save_highlight = not dict_popup.save_highlight

					local this_button = dict_popup.button_table:getButtonById("highlight")
					this_button:setIcon(dict_popup.save_highlight and "button.unhighlight" or "button.highlight", this_button.width)
					this_button:refresh()

					UIManager:setDirty("all", function()
						return "ui", dict_popup.dimen
					end)
				end
				highlightButton = button
			elseif button.id == "search" then
				button.text = nil
				button.icon = "button.search"
				searchButton = button
			elseif button.id == "wikipedia" then
				button.text_func = nil
				if dict_popup.is_wiki then
					button.icon = "button.article"
				else
					button.icon = "button.wikipedia"
				end
				wikipediaButton = button
			elseif button.id == "close" then
				button.text = nil
				button.icon = "close"
				closeButton = button
			elseif button.id == "wordreference" then
				button.text = nil
				button.icon = "button.wordreference"
				wordReferenceButton = button
			else
				table.insert(unknownButtons, button)
			end
		end
	end

	local translateButton = {
		id = "translate",
		icon = "button.translate",
		callback = function()
			Translator:showTranslation(dict_popup.word, true)
		end
	}

	local dictionaryButton = {
		id = "dictionary",
		icon = "button.dictionary",
		enabled = dict_popup.is_wiki,
		callback = function()
			self.ui.dictionary:onLookupWord(dict_popup.word, false, dict_popup.word_boxes, self.ui.highlight)
		end
	}

	-- Remove all rows.
	for row = 1, #buttons do
		table.remove(buttons, row)
	end

	-- Add custom rows.
	local currentRow = 1

	buttons[currentRow] = {
		vocabularyButton,
	}
	currentRow = currentRow + 1

	buttons[currentRow] = {
		prevDictButton,
		nextDictButton,
	}
	currentRow = currentRow + 1

	buttons[currentRow] = {
		highlightButton,
		wikipediaButton,
		wordReferenceButton,
		dictionaryButton,
		translateButton,
		searchButton,
	}
	currentRow = currentRow + 1

	if #unknownButtons > 0 then
		buttons[currentRow] = unknownButtons
		currentRow = currentRow + 1
	end

	-- Remove all `nil` buttons.
	for row = 1, #buttons do
		for column = #buttons[row], 1, -1 do
			if buttons[row][column] == nil then
				table.remove(buttons[row], column)
			end
		end
	end

	-- Remove all empty rows.
	for row = #buttons, 1, -1 do
		if #buttons[row] == 0 then
			table.remove(buttons, row)
		end
	end

	return false
end

function AdvancedReaderMenu:onWordReferenceDefinitionButtonsReady(ui, buttons)
	for row = 1, #buttons do
		for column = 1, #buttons[row] do
			local button = buttons[row][column]

			if button.id == "wikipedia" then
				button.text = nil
				button.icon = "button.wikipedia"
			elseif button.id == "dictionary" then
				button.text = nil
				button.icon = "button.dictionary"
			elseif button.id == "translate" then
				button.text = nil
				button.icon = "button.translate"
			end
		end
	end
end

return AdvancedReaderMenu