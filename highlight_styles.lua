local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderUI = require("apps/reader/readerui")
local ReaderView = require("apps/reader/modules/readerview")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local FocusManager = require("ui/widget/focusmanager")
local InputContainer = require("ui/widget/container/inputcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Size = require("ui/size")

local StyleSelectionDialog = FocusManager:extend{
    movable = nil,
    cancel_callback = nil,
    ges_events = {
        TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        }
    }
}

function StyleSelectionDialog:init()
    self[1] = require("ui/widget/container/centercontainer"):new{
        dimen = Screen:getSize(),
        self.movable,
    }
end

function StyleSelectionDialog:getContentSize()
    return self.movable.dimen
end

function StyleSelectionDialog:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.movable.dimen) then
        self:onClose()
    end
    return true
end

function StyleSelectionDialog:onClose()
    if self.cancel_callback then
        self.cancel_callback()
    end
    UIManager:close(self)
    return true
end

function StyleSelectionDialog:paintTo(...)
    FocusManager.paintTo(self, ...)
    self.dimen = self.movable.dimen
end

function StyleSelectionDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
end

function StyleSelectionDialog:onCloseWidget()
    UIManager:setDirty(nil, "ui")
end

local StyleButton = InputContainer:extend{
    style_drawer = nil,
    is_selected = false,
    is_focused = false,
    width = nil,
    height = nil,
    callback = nil,
}

function StyleButton:init()
    self.width = self.width or Screen:scaleBySize(44)
    self.height = self.height or Screen:scaleBySize(44)
    self.dimen = Geom:new{ w = self.width, h = self.height }

    local text = "U"
    if self.style_drawer == "lighten" then text = "H"
    elseif self.style_drawer == "invert" then text = "I"
    elseif self.style_drawer == "strikeout" then text = "S"
    end

    self.text_widget = require("ui/widget/textwidget"):new{
        text = text,
        face = require("ui/font"):getFace("cfont", 20),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.ges_events = {
        TapStyleButton = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
    }
end

function StyleButton:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y

    local bg_color = Blitbuffer.COLOR_WHITE
    if self.is_selected or self.is_focused then
        bg_color = Blitbuffer.COLOR_GRAY_E
    end
    
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, bg_color)
    
    if self.is_selected or self.is_focused then
        bb:paintBorder(x, y, self.dimen.w, self.dimen.h, Screen:scaleBySize(2), Blitbuffer.COLOR_BLACK)
    end

    -- Draw text first, so effects can be applied over it
    local tw = self.text_widget:getSize().w
    local th = self.text_widget:getSize().h
    self.text_widget:paintTo(bb, x + math.floor((self.dimen.w - tw) / 2), y + math.floor((self.dimen.h - th) / 2))

    local sample_color = Blitbuffer.COLOR_BLACK
    local sample_rect = Geom:new{
        x = x + Screen:scaleBySize(8),
        y = y + math.floor(self.dimen.h / 2) - Screen:scaleBySize(10),
        w = self.dimen.w - Screen:scaleBySize(16),
        h = Screen:scaleBySize(20)
    }

    if self.style_drawer == "lighten" then
        bb:darkenRect(sample_rect.x, sample_rect.y, sample_rect.w, sample_rect.h, 0.4)
    elseif self.style_drawer == "invert" then
        bb:invertRect(sample_rect.x, sample_rect.y, sample_rect.w, sample_rect.h)
    elseif self.style_drawer == "strikeout" then
        bb:paintRect(sample_rect.x, sample_rect.y + math.floor(sample_rect.h / 2), sample_rect.w, Size.line.thick, sample_color)
    else
        local view = ReaderUI.instance and ReaderUI.instance.view
        if view then
            local orig_thick = Size.line.medium
            Size.line.medium = Size.line.thick
            view:drawHighlightRect(bb, 0, 0, sample_rect, self.style_drawer, sample_color, false)
            Size.line.medium = orig_thick
        else
            bb:paintRect(sample_rect.x, sample_rect.y + sample_rect.h - 1, sample_rect.w, Size.line.thick, sample_color)
        end
    end
end

function StyleButton:onTapStyleButton()
    if self.callback then
        self.callback()
    end
    return true
end

function StyleButton:onFocus()
    self.is_focused = true
    self:refresh()
    return true
end

function StyleButton:onUnfocus()
    self.is_focused = false
    self:refresh()
    return true
end

function StyleButton:refresh()
    UIManager:setDirty(self, "ui")
end

function ReaderHighlight:showHighlightStyleDialog(caller_callback, curr_style, index)
    UIManager:nextTick(function()
        local active_width = self.screen_w or Screen:getWidth()
        local dialog_padding = 2 * (Size.border.window or 2) + 2 * (Size.padding.large or 15)
        local available_width = active_width - dialog_padding - Screen:scaleBySize(20)

        local orig_styles = ReaderHighlight.getHighlightStyles()
        local styles = {}
        local all_buttons = {}
        local order = { "lighten", "invert", "strikeout", "underscore" }
        local added = {}
        for _, k in ipairs(order) do
            for _, v in ipairs(orig_styles) do
                if v[2] == k then
                    table.insert(styles, v)
                    added[k] = true
                    break
                end
            end
        end
        for _, v in ipairs(orig_styles) do
            if not added[v[2]] then
                table.insert(styles, v)
            end
        end

        local N = #styles
        local button_padding = Screen:scaleBySize(8)
        local spacer_width = Screen:scaleBySize(6)

        -- Calculate a reasonable button size
        local max_w = math.floor((available_width - (N - 1) * spacer_width) / N)
        local bw = math.min(Screen:scaleBySize(44), math.max(Screen:scaleBySize(24), max_w))
        local bh = bw -- Square buttons

        -- If there are too many styles, we wrap to multiple lines
        local buttons_per_row = math.floor((available_width + spacer_width) / (bw + spacer_width))
        
        local rows = {}
        local current_group = nil

        local dialog

        for i, v in ipairs(styles) do
            local style_name, style = unpack(v)

            if (i - 1) % buttons_per_row == 0 then
                current_group = HorizontalGroup:new{ align = "center" }
                table.insert(rows, current_group)
            end

            local button = StyleButton:new{
                style_drawer = style,
                is_selected = (style == curr_style),
                width = bw,
                height = bh,
            }
            table.insert(all_buttons, button)
            
            button.callback = function()
                for _, b in ipairs(all_buttons) do
                    if b.is_selected then
                        b.is_selected = false
                        b:refresh()
                    end
                end
                button.is_selected = true
                button:refresh()

                caller_callback(style)
                UIManager:close(dialog)
            end

            table.insert(current_group, button)

            -- Add spacer if not the last item in the row
            if i % buttons_per_row ~= 0 and i < #styles then
                table.insert(current_group, HorizontalSpan:new{ width = spacer_width })
            end
        end

        -- Layout contains a vertical group of horizontal groups
        local layout_items = {}
        for r, row in ipairs(rows) do
            table.insert(layout_items, row)
            if r < #rows then
                -- Vertical spacing between rows
                table.insert(layout_items, require("ui/widget/verticalspan"):new{ height = spacer_width })
            end
        end

        local layout_group = require("ui/widget/verticalgroup"):new{
            align = "center",
            unpack(layout_items)
        }

        local dialog
        local movable = MovableContainer:new{
            anchor = function()
                if not index and not self.selected_text then return nil end
                return self:_getDialogAnchor(dialog, index)
            end,
            FrameContainer:new{
                background = Blitbuffer.COLOR_WHITE,
                bordersize = Size.border.window,
                radius = Size.radius.window,
                padding = Size.padding.large,
                layout_group,
            }
        }

        dialog = StyleSelectionDialog:new{
            movable = movable,
            cancel_callback = function()
                if self.selected_text then
                    self:clear()
                end
            end
        }

        -- Position the dialog below or above the highlight center, similar to color dialog
        -- For simplicity, we just use UIManager:show with center layout by default
        -- or we can mimic ReaderHighlight:_getDialogAnchor
        UIManager:show(dialog)
    end)
end
