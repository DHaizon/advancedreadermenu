local ReaderView = require("apps/reader/modules/readerview")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local Blitbuffer = require("ffi/blitbuffer")
local Size = require("ui/size")
local Device = require("device")
local _ = require("gettext")

local function initFancyUnderlines()
    local original_drawHighlightRect = ReaderView.drawHighlightRect

    -- Inject our new styles into the global highlight styles table
    local highlight_styles = ReaderHighlight.getHighlightStyles()
    
    local injected = false
    for _, style in ipairs(highlight_styles) do
        if style[2] == "double_underline" then
            injected = true
            break
        end
    end

    if not injected then
        table.insert(highlight_styles, {_("Double underline"), "double_underline"})
        table.insert(highlight_styles, {_("Dashed line"), "dashed"})
        table.insert(highlight_styles, {_("Dotted line"), "dotted"})
        table.insert(highlight_styles, {_("Zig-zag"), "zigzag"})
        table.insert(highlight_styles, {_("Wave"), "wave"})
    end

    -- Monkey-patch drawHighlightRect
    local orig = original_drawHighlightRect
    ReaderView.drawHighlightRect = function(view_self, bb, _x, _y, rect, drawer, color, draw_note_mark)
        local custom_drawers = {
            double_underline = true,
            dashed = true,
            dotted = true,
            zigzag = true,
            wave = true,
        }

        if custom_drawers[drawer] then
            local x, y, w, h = rect.x, rect.y, rect.w, rect.h
            
            local is_color8 = true
            if type(color) == "table" and color._bw_pattern then
                is_color8 = true
                color = Blitbuffer.COLOR_GRAY_4
            elseif type(color) == "string" then
                is_color8 = false
                color = Blitbuffer.hexToRGB32(color)
            else
                is_color8 = Blitbuffer.isColor8(color)
            end
            color = color or Blitbuffer.COLOR_GRAY_4

            if drawer == "double_underline" then
                if is_color8 then
                    bb:paintRect(x, y + h - 3, w, Size.line.thick, color)
                    bb:paintRect(x, y + h, w, Size.line.thick, color)
                else
                    bb:paintRectRGB32(x, y + h - 3, w, Size.line.thick, color)
                    bb:paintRectRGB32(x, y + h, w, Size.line.thick, color)
                end

            elseif drawer == "dashed" then
                local dash_len = 8
                local gap_len = 4
                for i = 0, w, dash_len + gap_len do
                    local dw = math.min(dash_len, w - i)
                    if dw > 0 then
                        if is_color8 then
                            bb:paintRect(x + i, y + h - 1, dw, Size.line.thick, color)
                        else
                            bb:paintRectRGB32(x + i, y + h - 1, dw, Size.line.thick, color)
                        end
                    end
                end

            elseif drawer == "dotted" then
                local dot_len = 3
                local gap_len = 3
                for i = 0, w, dot_len + gap_len do
                    local dw = math.min(dot_len, w - i)
                    if dw > 0 then
                        if is_color8 then
                            bb:paintRect(x + i, y + h - 1, dw, Size.line.thick, color)
                        else
                            bb:paintRectRGB32(x + i, y + h - 1, dw, Size.line.thick, color)
                        end
                    end
                end

            elseif drawer == "zigzag" then
                local zig_w = 5
                local zig_h = 5
                local cy = y + h - 2
                for i = 0, w - 1 do
                    local phase = i % (zig_w * 2)
                    local dy = 0
                    if phase < zig_w then
                        dy = phase * zig_h / zig_w
                    else
                        dy = (zig_w * 2 - phase) * zig_h / zig_w
                    end
                    dy = math.floor(dy + 0.5) - math.floor(zig_h / 2)
                    
                    if is_color8 then
                        bb:paintRect(x + i, cy + dy, 1, Size.line.thick, color)
                    else
                        bb:paintRectRGB32(x + i, cy + dy, 1, Size.line.thick, color)
                    end
                end

            elseif drawer == "wave" then
                local wave_w = 7
                local wave_h = 4
                local cy = y + h - 2
                for i = 0, w - 1 do
                    local dy = math.floor(math.sin(i / wave_w * math.pi) * wave_h + 0.5)
                    
                    if is_color8 then
                        bb:paintRect(x + i, cy + dy, 1, Size.line.thick, color)
                    else
                        bb:paintRectRGB32(x + i, cy + dy, 1, Size.line.thick, color)
                    end
                end
            end

            -- Also draw the note mark if needed (copied from original readerview.lua)
            if view_self.highlight.note_mark ~= nil and draw_note_mark ~= nil then
                color = color or Blitbuffer.COLOR_BLACK
                if view_self.highlight.note_mark == "underline" then
                    -- With most annotation styles, we'd risk making this invisible if we used the same color,
                    -- so, always draw this in black.
                    if is_color8 then
                        bb:paintRect(x, y + h - 1, w, Size.line.medium, Blitbuffer.COLOR_BLACK)
                    else
                        -- Blitbuffer.COLOR_BLACK is normally 0 for 8-bit. For RGB32, we should use COLOR_BLACK as well
                        -- Wait, if color8 uses paintRect, RGB32 uses paintRectRGB32 with an RGB color. 
                        -- It's simpler to just let original code handle it if it gets complicated,
                        -- but we already have the RGB32 color for black if we pass it correctly.
                        -- Actually, let's just use `bb:paintRect` for black in 8-bit, 
                        -- or `Blitbuffer.COLOR_BLACK` which is 0. 
                        -- To be safe, let's just check if Blitbuffer.COLOR_BLACK is a table.
                        bb:paintRect(x, y + h - 1, w, Size.line.medium, Blitbuffer.COLOR_BLACK)
                    end
                else
                    local note_mark_pos_x
                    if view_self.ui.paging or
                            (view_self.document:getVisiblePageCount() == 1) or 
                            (x < Device.screen:getWidth() / 2) then 
                        note_mark_pos_x = view_self.note_mark_pos_x1
                    else
                        note_mark_pos_x = view_self.note_mark_pos_x2
                    end
                    if view_self.highlight.note_mark == "sideline" then
                        if is_color8 then
                            bb:paintRect(note_mark_pos_x, y, view_self.note_mark_line_w, rect.h, color)
                        else
                            bb:paintRectRGB32(note_mark_pos_x, y, view_self.note_mark_line_w, rect.h, color)
                        end
                    elseif view_self.highlight.note_mark == "sidemark" then
                        if draw_note_mark then
                            view_self.note_mark_sign:paintTo(bb, note_mark_pos_x, y)
                        end
                    end
                end
            end
        else
            orig(view_self, bb, _x, _y, rect, drawer, color, draw_note_mark)
        end
    end
end

return initFancyUnderlines
