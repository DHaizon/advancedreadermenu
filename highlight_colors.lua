local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ColorWheelWidget = require("widgets/colorwheelwidget")
local InputDialog = require("ui/widget/inputdialog")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderUI = require("apps/reader/readerui")
local ReaderView = require("apps/reader/modules/readerview")
local Screen = require("device").screen
local Setting = require("lib/setting")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local common = require("lib/common")
local FocusManager = require("ui/widget/focusmanager")
local InputContainer = require("ui/widget/container/inputcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Size = require("ui/size")
local Device = require("device")
local Event = require("ui/event")

local HIGHLIGHT_COLOR_KEYS = {
    "gris-oscuro",
    "gris-medio",
    "gris-claro",
    "puntos",
    "diagonal-der",
    "diagonal-izq",
    "horizontal",
    "vertical",
    "cuadricula",
    "rombos",
}

local DEFAULT_HIGHLIGHT_COLOR_NAMES = {
    _("Gris oscuro"),
    _("Gris medio"),
    _("Gris claro"),
    _("Puntos"),
    _("Diagonal \\"),
    _("Diagonal //"),
    _("Horizontal --"),
    _("Vertical ||"),
    _("Cuadricula"),
    _("Rombos"),
}

-- Hex solo para la preview en el diálogo (en B&N se ven todos como grises)
local DEFAULT_HIGHLIGHT_COLOR_HEXES = {
    "#808080",
    "#B0B0B0",
    "#E0E0E0",
    "#A0A0A0",
    "#A0A0A0",
    "#A0A0A0",
    "#A0A0A0",
    "#A0A0A0",
    "#A0A0A0",
    "#A0A0A0",
}

local DEFAULT_HIGHLIGHT_COLORS = {}
for i, color in ipairs(HIGHLIGHT_COLOR_KEYS) do
    DEFAULT_HIGHLIGHT_COLORS[color] = { DEFAULT_HIGHLIGHT_COLOR_NAMES[i], DEFAULT_HIGHLIGHT_COLOR_HEXES[i] }
end

local FALLBACK_COLOR = "gris-medio"

-- Conjunto de claves que son patrones B&N (definido aquí para usarse en todo el archivo)
local BW_PATTERNS = {}
for _, k in ipairs(HIGHLIGHT_COLOR_KEYS) do BW_PATTERNS[k] = true end

-- Settings
local HighlightColors = Setting("book_highlight_colors", DEFAULT_HIGHLIGHT_COLORS)
local DefaultHighlightColor = Setting("highlight_color", FALLBACK_COLOR, true)

local function getHighlightColorIndex(color)
    for i, key in ipairs(HIGHLIGHT_COLOR_KEYS) do
        if key == color then
            return i
        end
    end
end

local original_getHighlightColorString = ReaderHighlight.getHighlightColorString
function ReaderHighlight:getHighlightColorString(color)
    local color_data = HighlightColors.get()[color]
    if color_data then
        return color_data[1]
    end
    if original_getHighlightColorString then
        return original_getHighlightColorString(self, color)
    end
    return color
end

local function setHighlightColorString(color, color_string)
    local colors = HighlightColors.get()
    colors[color][1] = color_string
    HighlightColors.set(colors)
end

local function getHighlightColorHex(color)
    local color_data = HighlightColors.get()[color]
    return color_data and color_data[2]
end

local function setHighlightColorHex(color, hex)
    local colors = HighlightColors.get()
    colors[color][2] = hex
    HighlightColors.set(colors)

    Blitbuffer.HIGHLIGHT_COLORS[color] = hex

    if common.has_document_open() then
        ReaderUI.instance.view:resetHighlightBoxesCache()
    end
end

local original_getHighlightColor = ReaderHighlight.getHighlightColor
function ReaderHighlight:getHighlightColor(color)
    if BW_PATTERNS[color] then
        return Blitbuffer.COLOR_GRAY_B  -- gris para preview en el diálogo
    end
    local color_data = HighlightColors.get()[color]
    local hex = color_data and color_data[2]
    if hex then
        if Screen.night_mode then
            hex = common.invertColor(hex)
        end
        return Blitbuffer.colorFromString(hex)
    end
    if original_getHighlightColor then
        return original_getHighlightColor(self, color)
    end
    return Blitbuffer.gray(G_reader_settings:readSetting("highlight_lighten_factor") or 0.2)
end

-- Updates the highlight color k-v pair tables (responsible for shown color names and values)
local function update_highlight_color_pairs(self)
    self.highlight_colors = {}
    local colors = HighlightColors.get()
    for i, color in ipairs(HIGHLIGHT_COLOR_KEYS) do
        self.highlight_colors[i] = { colors[color][1], color }
        Blitbuffer.HIGHLIGHT_COLORS[color] = colors[color][2]
    end
end

-- Update highlight color pairs on reader highlight init
local original_ReaderHighlight_init = ReaderHighlight.init
function ReaderHighlight:init()
    update_highlight_color_pairs(self)

    original_ReaderHighlight_init(self)
end

-- Update highlight color pairs on editing highlight color
local original_ReaderHighlight_editHighlightColor = ReaderHighlight.editHighlightColor
function ReaderHighlight:editHighlightColor(index)
    update_highlight_color_pairs(self)
    local curr_color = self.ui.annotation.annotations[index].color
    self:showHighlightColorDialog(function(color)
        if color ~= curr_color then
            self.ui.annotation.annotations[index].color = color
            self.ui:handleEvent(Event:new("AnnotationsModified", { self.ui.annotation.annotations[index] }))
            self:writePdfAnnotation("save", self.ui.annotation.annotations[index])
            UIManager:setDirty(self.dialog, "ui")
        end
    end, curr_color, index)
end

-- Menus
local function set_color_menu(touchmenu_instance, original_hex, callback)
    original_hex = original_hex or "#333333"

    local input_dialog
    input_dialog = InputDialog:new({
        title = _("Enter highlight color code"),
        input = original_hex,
        input_hint = "#FFFFFF",
        buttons = {
            {
                {
                    text = "Cancel",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = "Next",
                    callback = function()
                        local text = input_dialog:getInputText()

                        if text ~= "" then
                            if not text:match("^#%x%x%x%x%x%x$") then
                                return
                            end

                            callback(text)

                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                            UIManager:close(input_dialog)
                        end
                    end,
                },
            },
        },
    })
    return input_dialog
end

local function pick_color_menu(touchmenu_instance, original_hex, callback)
    original_hex = original_hex or "#333333"

    local h, s, v = common.hexToHSV(original_hex)
    local wheel
    wheel = ColorWheelWidget:new({
        title_text = _("Pick highlight color"),
        hue = h,
        saturation = s,
        value = v,
        invert_in_night_mode = true,
        callback = function(hex)
            callback(hex)

            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
            UIManager:setDirty(nil, "ui")
        end,
        cancel_callback = function()
            UIManager:setDirty(nil, "ui")
        end,
    })
    return wheel
end

-- Menu to select method for choosing color
local function color_menu(touchmenu_instance, original_hex, callback)
    local dialog = MultiConfirmBox:new({
        text = _("Choose the highlight color by:"),
        choice1_text = _("Hex code"),
        choice1_callback = function()
            local input_dialog = set_color_menu(touchmenu_instance, original_hex, callback)
            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end,
        choice2_text = _("Color picker"),
        choice2_callback = function()
            UIManager:show(pick_color_menu(touchmenu_instance, original_hex, callback))
        end,
    })
    return dialog
end

local edit_menu

local function highlightColorDialog(touchmenu_instance)
    local dialog
    local buttons = {}
    local default_highlight_color = DefaultHighlightColor.get()
    for i, color in ipairs(HIGHLIGHT_COLOR_KEYS) do
        local text = ReaderHighlight.getHighlightColorString(nil, color)
        if color == default_highlight_color then
            text = text .. " ★"
        end
        buttons[i] = { {
            text = text,
            menu_style = true,
            background = ReaderHighlight.getHighlightColor(nil, color),
            callback = function()
                local original_hex = getHighlightColorHex(color)
                UIManager:show(color_menu(touchmenu_instance, original_hex, function(hex)
                    setHighlightColorHex(color, hex)
                    UIManager:close(dialog)
                    UIManager:show(highlightColorDialog(touchmenu_instance))
                end))
            end,
            hold_callback = function()
                UIManager:show(edit_menu(touchmenu_instance, color, { dialog = dialog }))
            end
        } }
    end
    dialog = ButtonDialog:new {
        buttons = buttons,
        width_factor = 0.4,
        colorful = true,
        dithered = true,
    }
    return dialog
end

edit_menu = function(touchmenu_instance, color, updialog_ref)
    local button_bg_colors = {
        Blitbuffer.colorFromString("#BA8E23"),
        Blitbuffer.colorFromString("#2D728F"),
        Blitbuffer.colorFromString("#DC6BAD"),
        Blitbuffer.colorFromString("#FF5964"),
    }

    for i, bg_color in ipairs(button_bg_colors) do
        if Screen.night_mode then
            button_bg_colors[i] = bg_color:invert()
        end
    end

    local dialog

    local edit_buttons = {
        { {
            text = _("§white ✒ Rename§r "),
            menu_style = true,
            original_background = button_bg_colors[1],
            background = common.EXCLUSION_COLOR,
            callback = function()
                local input_dialog
                input_dialog = InputDialog:new({
                    title = "Enter the color's new name:",
                    input = ReaderHighlight.getHighlightColorString(nil, color),
                    buttons = {
                        {
                            {
                                text = "Cancel",
                                callback = function()
                                    UIManager:close(input_dialog)
                                end,
                            },
                            {
                                text = "Save",
                                callback = function()
                                    local text = input_dialog:getInputText()

                                    if text ~= "" then
                                        setHighlightColorString(color, text)

                                        UIManager:close(input_dialog)
                                        UIManager:close(dialog)

                                        UIManager:close(updialog_ref.dialog)
                                        UIManager:show(highlightColorDialog(touchmenu_instance))
                                    end
                                end,
                            }
                        }
                    }
                })
                UIManager:show(input_dialog)
                input_dialog:onShowKeyboard()
            end,
        } },
        { {
            text = _("§white ● Edit color§r "),
            menu_style = true,
            original_background = button_bg_colors[2],
            background = common.EXCLUSION_COLOR,
            callback = function()
                UIManager:show(color_menu(touchmenu_instance, getHighlightColorHex(color), function(hex)
                    setHighlightColorHex(color, hex)

                    UIManager:close(dialog)

                    UIManager:close(updialog_ref.dialog)
                    UIManager:show(highlightColorDialog(touchmenu_instance))
                end))

                UIManager:close(dialog)
            end,
        } },
        { {
            text = _("§white ★ Make default§r "),
            menu_style = true,
            original_background = button_bg_colors[3],
            background = common.EXCLUSION_COLOR,
            callback = function()
                DefaultHighlightColor.set(color)

                UIManager:close(dialog)

                UIManager:close(updialog_ref.dialog)
                UIManager:show(highlightColorDialog(touchmenu_instance))
            end,
        } },
        { {
            text = _("§white ⟳ Reset§r "),
            menu_style = true,
            original_background = button_bg_colors[4],
            background = common.EXCLUSION_COLOR,
            callback = function()
                setHighlightColorString(color, DEFAULT_HIGHLIGHT_COLOR_NAMES[getHighlightColorIndex(color)])
                setHighlightColorHex(color, DEFAULT_HIGHLIGHT_COLOR_HEXES[getHighlightColorIndex(color)])

                UIManager:close(dialog)

                UIManager:close(updialog_ref.dialog)
                UIManager:show(highlightColorDialog(touchmenu_instance))
            end,
        } },
    }

    dialog = ButtonDialog:new {
        buttons = edit_buttons,
        width_factor = 0.3,
        colorful = true,
        dithered = true,
    }
    return dialog
end

-- ─── Patrones B&N ────────────────────────────────────────────────────────────
-- readerview.lua convierte item.color (string) a objeto Blitbuffer con
-- colorFromName() ANTES de llamar a drawHighlightRect. Para nuestros patrones
-- ese nombre es desconocido → devuelve nil → se dibuja gris por defecto.
--
-- Solución: parcheamos colorFromName para que, cuando reciba un nombre de
-- patrón nuestro, guarde el nombre en _pending_pattern y devuelva un gris
-- válido. drawHighlightRect lee y consume _pending_pattern inmediatamente.
-- Como colorFromName y drawHighlightRect se llaman en el mismo hilo de forma
-- sincrónica (sin corrutinas entre medias), esto es seguro.

local orig_colorFromName = Blitbuffer.colorFromName
Blitbuffer.colorFromName = function(name)
    if BW_PATTERNS[name] then
        -- Tabla que actúa como "color" y lleva el nombre del patrón.
        -- Se guarda en page_boxes.color, así sobrevive al cache entre renders.
        return { _bw_pattern = name }
    end
    return orig_colorFromName(name)
end

-- isColor8 recibe nuestras tablas de patrón — devolvemos true (escala de grises)
-- para que KOReader no marque la página como "colorida"
local orig_isColor8 = Blitbuffer.isColor8
Blitbuffer.isColor8 = function(color)
    if type(color) == "table" and color._bw_pattern then return true end
    return orig_isColor8(color)
end

local COLOR_MARK = Blitbuffer.COLOR_GRAY_4

local function drawPattern(bb, x, y, w, h, p)
    local factor = 0.75  -- intensidad del oscurecimiento para los trazos

    if p == "gris-claro" then
        bb:darkenRect(x, y, w, h, 0.15)
    elseif p == "gris-medio" then
        bb:darkenRect(x, y, w, h, 0.35)
    elseif p == "gris-oscuro" then
        bb:darkenRect(x, y, w, h, 0.6)

    elseif p == "puntos" then
        -- Puntos 2x2 cada 5px usando darkenRect en cada punto
        local py = y
        while py < y+h do
            local ph = math.min(2, y+h-py)
            local px = x
            while px < x+w do
                local pw = math.min(2, x+w-px)
                bb:darkenRect(px, py, pw, ph, factor)
                px = px + 5
            end
            py = py + 5
        end

    elseif p == "diagonal-der" then
        -- Rayas \\\\ : para cada fila, la columna de inicio se desplaza
        for py = y, y+h-1 do
            local offset = (py - y) % 16
            local px = x + offset
            while px < x+w do
                local pw = math.min(2, x+w-px)
                bb:darkenRect(px, py, pw, 1, factor)
                px = px + 16
            end
        end

    elseif p == "diagonal-izq" then
        -- Rayas //// : desplazamiento inverso
        for py = y, y+h-1 do
            local offset = (y+h-1 - py) % 16
            local px = x + offset
            while px < x+w do
                local pw = math.min(2, x+w-px)
                bb:darkenRect(px, py, pw, 1, factor)
                px = px + 16
            end
        end

    elseif p == "horizontal" then
        -- Líneas horizontales cada 6px
        local py = y
        while py < y+h do
            local ph = math.min(2, y+h-py)
            bb:darkenRect(x, py, w, ph, factor)
            py = py + 16
        end

    elseif p == "vertical" then
        -- Líneas verticales cada 6px
        local px = x
        while px < x+w do
            local pw = math.min(2, x+w-px)
            bb:darkenRect(px, y, pw, h, factor)
            px = px + 16
        end

    elseif p == "cuadricula" then
        -- Horizontal + vertical cada 6px
        local py = y
        while py < y+h do
            local ph = math.min(1, y+h-py)
            bb:darkenRect(x, py, w, ph, factor)
            py = py + 16
        end
        local px = x
        while px < x+w do
            local pw = math.min(1, x+w-px)
            bb:darkenRect(px, y, pw, h, factor)
            px = px + 16
        end

    elseif p == "rombos" then
        -- Diagonal-der + diagonal-izq superpuestas
        for py = y, y+h-1 do
            local off1 = (py - y) % 24
            local px1 = x + off1
            while px1 < x+w do
                local pw = math.min(2, x+w-px1)
                bb:darkenRect(px1, py, pw, 1, factor)
                px1 = px1 + 24
            end
            local off2 = (y+h-1 - py) % 24
            local px2 = x + off2
            while px2 < x+w do
                local pw = math.min(2, x+w-px2)
                bb:darkenRect(px2, py, pw, 1, factor)
                px2 = px2 + 24
            end
        end
    end
end

local orig_drawHighlightRect = ReaderView.drawHighlightRect
ReaderView.drawHighlightRect = function(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
    local pattern = type(color) == "table" and color._bw_pattern or nil

    if drawer == "lighten" and pattern then
        local x, y, w, h = rect.x, rect.y, rect.w, rect.h
        local pct = G_reader_settings:readSetting("highlight_height_pct")
        if pct ~= nil then
            h = math.floor(h * pct / 100)
            y = y + math.ceil((rect.h - h) / 2)
        end
        drawPattern(bb, x, y, w, h, pattern)
        if self.highlight.note_mark ~= nil and draw_note_mark ~= nil then
            if self.highlight.note_mark == "underline" then
                bb:paintRect(x, y + h - 1, w, 1, Blitbuffer.COLOR_BLACK)
            end
        end
        return
    end

    if pattern then
        color = Blitbuffer.COLOR_GRAY_4
    end
    return orig_drawHighlightRect(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
end

-- ─── Custom horizontal circular highlight color selection menu ───────────────────
local CircleColorButton = InputContainer:extend{
    pattern_name = nil,
    color_value = nil,
    is_selected = false,
    is_focused = false,
    radius = nil,
    callback = nil,
}

local function paintPatternCircle(bb, cx, cy, r, pattern_name, color_value)
    local bg_color = Blitbuffer.colorFromString("#F2F2F2")
    local fg_color = Blitbuffer.COLOR_GRAY_4

    if pattern_name == "gris-claro" or pattern_name == "gris-medio" or pattern_name == "gris-oscuro" then
        bb:paintCircle(cx, cy, r, color_value)
        return
    end

    for dy = -r, r do
        local y = cy + dy
        local dy_sq = dy * dy
        for dx = -r, r do
            local x = cx + dx
            if dx * dx + dy_sq <= r * r then
                local is_fg = false
                if pattern_name == "puntos" then
                    is_fg = (dx % 5 < 2) and (dy % 5 < 2)
                elseif pattern_name == "diagonal-der" then
                    is_fg = (dx - dy) % 10 < 2
                elseif pattern_name == "diagonal-izq" then
                    is_fg = (dx + dy) % 10 < 2
                elseif pattern_name == "horizontal" then
                    is_fg = dy % 8 < 2
                elseif pattern_name == "vertical" then
                    is_fg = dx % 8 < 2
                elseif pattern_name == "cuadricula" then
                    is_fg = (dx % 10 < 1) or (dy % 10 < 1)
                elseif pattern_name == "rombos" then
                    is_fg = ((dx - dy) % 12 < 2) or ((dx + dy) % 12 < 2)
                end

                if is_fg then
                    bb:setPixelClamped(x, y, fg_color)
                else
                    bb:setPixelClamped(x, y, bg_color)
                end
            end
        end
    end

    bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_GRAY, 1)
end

function CircleColorButton:init()
    self.radius = self.radius or Screen:scaleBySize(18)
    local size = self.radius * 2 + Screen:scaleBySize(10)
    self.dimen = Geom:new{ w = size, h = size }

    self.ges_events = {
        TapColorButton = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
    }
end

function CircleColorButton:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y

    local cx = x + self.dimen.w / 2
    local cy = y + self.dimen.h / 2

    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)

    if self.is_selected or self.is_focused then
        bb:paintCircle(cx, cy, self.radius + Screen:scaleBySize(3), Blitbuffer.COLOR_BLACK, Screen:scaleBySize(2))
    end

    paintPatternCircle(bb, cx, cy, self.radius, self.pattern_name, self.color_value)
end

function CircleColorButton:onTapColorButton()
    if self.callback then
        self.callback()
    end
    return true
end

function CircleColorButton:onFocus()
    self.is_focused = true
    self:refresh()
    return true
end

function CircleColorButton:onUnfocus()
    self.is_focused = false
    self:refresh()
    return true
end

function CircleColorButton:refresh()
    UIManager:setDirty(self, "ui")
end

local ColorSelectionDialog = FocusManager:extend{
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

function ColorSelectionDialog:init()
    self[1] = require("ui/widget/container/centercontainer"):new{
        dimen = Screen:getSize(),
        self.movable,
    }
end

function ColorSelectionDialog:getContentSize()
    return self.movable.dimen
end

function ColorSelectionDialog:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.movable.dimen) then
        self:onClose()
    end
    return true
end

function ColorSelectionDialog:onClose()
    if self.cancel_callback then
        self.cancel_callback()
    end
    UIManager:close(self)
    return true
end

function ColorSelectionDialog:paintTo(...)
    FocusManager.paintTo(self, ...)
    self.dimen = self.movable.dimen
end

function ColorSelectionDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
end

function ColorSelectionDialog:onCloseWidget()
    UIManager:setDirty(nil, "ui")
end

function ReaderHighlight:showHighlightColorDialog(caller_callback, curr_color, index)
    UIManager:nextTick(function()
        local active_width = self.screen_w or Screen:getWidth()
        local dialog_padding = 2 * (Size.border.window or 2) + 2 * (Size.padding.large or 15)
        local available_width = active_width - dialog_padding - Screen:scaleBySize(20)

        local N = #self.highlight_colors
        local button_padding = Screen:scaleBySize(10)
        local spacer_width = Screen:scaleBySize(8)

        local max_r = math.floor((available_width - N * button_padding - (N - 1) * spacer_width) / (2 * N))
        local r = math.min(Screen:scaleBySize(18), math.max(1, max_r))

        local buttons_group = HorizontalGroup:new{
            align = "center",
        }

        local layout = { {} }
        local dialog

        for i, v in ipairs(self.highlight_colors) do
            local color_name, color = unpack(v)
            local color_data = HighlightColors.get()[color]
            local hex = color_data and color_data[2]
            local color_val = hex and Blitbuffer.colorFromString(hex) or self:getHighlightColor(color)

            local button = CircleColorButton:new{
                pattern_name = color,
                color_value = color_val,
                is_selected = (color == curr_color),
                radius = r,
            }
            button.callback = function()
                caller_callback(color)
                UIManager:close(dialog)
            end

            table.insert(buttons_group, button)
            table.insert(layout[1], button)

            if i < #self.highlight_colors then
                table.insert(buttons_group, HorizontalSpan:new{ width = Screen:scaleBySize(8) })
            end
        end

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
                buttons_group,
            }
        }

        dialog = ColorSelectionDialog:new{
            movable = movable,
            cancel_callback = function()
                if index then
                    self:deleteHighlight(index)
                    UIManager:setDirty(self.dialog, "ui")
                elseif self.selected_text then
                    self:clear()
                end
            end,
        }

        -- Pre-calculate the anchor position so that UIManager dirties the correct region on show
        local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
        local content_size = movable[1]:getSize()
        local cx = math.floor((screen_w - content_size.w) / 2)
        local cy = math.floor((screen_h - content_size.h) / 2)
        movable.dimen = Geom:new{
            x = cx,
            y = cy,
            w = content_size.w,
            h = content_size.h,
        }

        UIManager:show(dialog)
    end)
end
-- ─────────────────────────────────────────────────────────────────────────────

-- Menu removed for integration with readermenuredesign
return true
