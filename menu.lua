------------------------------------------------------------
-- Menu visuals (Material Design)

local mp = require('mp')
local assdraw = require('mp.assdraw')
local Menu = {}
local MenuItem = assdraw.ass_new()

-- Material Design Google Dark Theme Colors
MenuItem.BG_NORMAL = "202124"        -- Surface color
MenuItem.BG_SELECTED = "3C4043"      -- Surface variant (hover)
MenuItem.TEXT_NORMAL = "9AA0A6"      -- On-surface muted
MenuItem.TEXT_SELECTED = "E8EAED"    -- On-surface bright
MenuItem.ACCENT_COLOR = "8AB4F8"     -- Google Blue
MenuItem.BORDER_COLOR = "3C4043"     -- Outline
MenuItem.DEFAULT_FONT_SIZE = 22
MenuItem.DEFAULT_WIDTH = 800
MenuItem.DEFAULT_HEIGHT = 48
MenuItem.CORNER_RADIUS = 8

function MenuItem:new(opts)
    local new = {}
    new.display_text = opts.display_text
    new.is_enabled = opts.is_enabled == nil and true or opts.is_enabled
    new.is_visible = opts.is_visible == nil and true or opts.is_visible
    new.on_chosen_cb = opts.on_chosen_cb
    new.on_selected_cb = opts.on_selected_cb or function() end
    
    new.font_size = opts.font_size or self.DEFAULT_FONT_SIZE
    new.width = opts.width or self.DEFAULT_WIDTH
    new.height = opts.height or self.DEFAULT_HEIGHT
    new.is_selected = false
    
    -- Custom colors per item (optional)
    new.custom_text_color = opts.text_color
    
    return setmetatable(new, {
        __index = self,
        __tostring = function(x)
            local string_rep = {}
            for k,v in pairs(x) do
                table.insert(string_rep, ("%s=%s"):format(k,v))
            end
            return ("MenuItem { %s }"):format(table.concat(string_rep, ", "))
        end
    })
end

function MenuItem:is_selectable()
    return self.is_enabled == true and self.is_visible == true
end

function MenuItem:apply_rect_color()
    local fill = (self.is_selected and self:is_selectable()) and self.BG_SELECTED or self.BG_NORMAL
    local fill_ass = fill:sub(5,6) .. fill:sub(3,4) .. fill:sub(1,2)
    local border_ass = self.BORDER_COLOR:sub(5,6) .. self.BORDER_COLOR:sub(3,4) .. self.BORDER_COLOR:sub(1,2)
    
    -- Fill: 1A (90% opaque), Border: 1px 88 alpha, Shadow: 2px offset AA alpha black
    self:append(string.format("{\\1c&H%s&\\1a&H1A&\\3c&H%s&\\3a&H88&\\bord1\\4c&H000000&\\4a&HAA&\\shad2}", fill_ass, border_ass))
end

function MenuItem:apply_text_color()
    local color = self.custom_text_color
    if not color then
        color = (self.is_selected and self:is_selectable()) and self.TEXT_SELECTED or self.TEXT_NORMAL
    end
    local color_ass = color:sub(5,6) .. color:sub(3,4) .. color:sub(1,2)
    -- Text needs no shadow or border for a flat Material look
    self:append(string.format("{\\1c&H%s&\\1a&H00&\\bord0\\shad0}", color_ass))
end

function MenuItem:draw(display_idx)
    self.text = ''
    -- Add a 4px gap between menu items
    local x0 = self.parent.pos_x
    local y0 = self.parent.pos_y + ((display_idx-1) * (self.height + 4))
    
    self:new_event()
    self:apply_rect_color()
    self:draw_start()
    self:pos(x0, y0)
    
    if self.round_rect_cw then
        self:round_rect_cw(0, 0, self.width, self.height, self.CORNER_RADIUS)
    else
        self:rect_cw(0, 0, self.width, self.height)
    end
    self:draw_stop()
    
    self:draw_text(display_idx, x0, y0)
    return self.text
end

function MenuItem:draw_text(display_idx, x0, y0)
    self:new_event()
    
    -- Center text vertically using {\an4}
    local text_x = x0 + self.parent.padding + 15
    local text_y = y0 + (self.height / 2)
    self:pos(text_x, text_y)
    
    -- Use a clean sans-serif font (Roboto or fallback)
    self:append(string.format([[{\fnRoboto\fs%s\an4}]], self.font_size))
    self:apply_text_color()
    
    local prefix = ""
    if self.is_selected and self:is_selectable() then
        -- Google Blue bullet indicator
        prefix = string.format("{\\1c&H%s%s%s&}● {\\1c&H%s%s%s&}", 
            self.ACCENT_COLOR:sub(5,6), self.ACCENT_COLOR:sub(3,4), self.ACCENT_COLOR:sub(1,2),
            self.TEXT_SELECTED:sub(5,6), self.TEXT_SELECTED:sub(3,4), self.TEXT_SELECTED:sub(1,2))
    else
        prefix = "   " 
    end
    
    -- Force custom color for header if needed
    if self.custom_text_color then
        local hc = self.custom_text_color
        prefix = string.format("{\\1c&H%s%s%s&}", hc:sub(5,6), hc:sub(3,4), hc:sub(1,2)) .. prefix
    end
    
    self:append(prefix .. self.display_text)
end

function Menu:new(o)
    self.__index = self
    o = o or {}
    o.header = o.header
    o.options = o.options or {}
    o.choices = o.choices or {}
    o.canvas_width = o.canvas_width or 1280
    o.canvas_height = o.canvas_height or 720
    o.on_close_callbacks = {}
    o.pos_x = o.pos_x or 50  -- Keep standard padding from screen edge
    o.pos_y = o.pos_y or 50
    o.padding = o.padding or 5
    o.visible_item_count = o.visible_item_count or 8  -- Increased visible items
    return setmetatable(o, self)
end

function Menu:set_header(header_text)
    self.header = MenuItem:new {
        is_enabled = false,
        is_visible = true,
        display_text = header_text,
        text_color = '8AB4F8', -- Google Blue
        font_size = 24
    }
    self.header.parent = self
end

function Menu:new_item(item_opts)
    local new = MenuItem:new(item_opts)
    new.parent = self
    return new
end

function Menu:add(choice)
    table.insert(self.choices, choice)
end

function Menu:add_item(item_opts)
    self:add(self:new_item(item_opts))
end

function Menu:add_option(item_opts)
    table.insert(self.options, self:new_item(item_opts))
    return self.options[#self.options]
end

function Menu:clear_choices(with_redraw)
    self.choices = {}
    if with_redraw then
        self:draw()
    end
end

function Menu:on_close(callback)
    table.insert(self.on_close_callbacks, callback)
end

function Menu:get_visible_items()
    local current_selection = self:get_selected_item()
    local displayed_items = {}
    table.insert(displayed_items, self.header)
    for _,option in ipairs(self.options) do
        table.insert(displayed_items, option)
    end
    local visible_selected_idx = 1
    for _,item in ipairs(self.choices) do
        if item.is_visible then
            if item == current_selection then
                break
            end
            visible_selected_idx = visible_selected_idx + 1
        end
    end

    local function is_within_window(item_idx)
        --print(("selected idx: %d, visible_selected_idx: %d, visible_item_count: %d"):format(item_idx + #self.options, visible_selected_idx, self.visible_item_count))
        return math.abs(item_idx - visible_selected_idx - 1) <= self.visible_item_count
    end

    local non_item_size, visible_idx = #displayed_items, 0
    for _,item in ipairs(self.choices) do
        if item.is_visible then
            visible_idx = visible_idx + 1
            -- Bug 20 fix: correct window centering; window shows items within visible_item_count of selected
            if (self.selected <= #self.options) or math.abs(visible_idx - visible_selected_idx) < self.visible_item_count then
                table.insert(displayed_items, item)
            end
        end
        if #displayed_items == self.visible_item_count + non_item_size then
            break
        end
    end
    return displayed_items
end

function Menu:draw()
    self.text_table = {}
    for i,item in ipairs(self:get_visible_items()) do
        table.insert(self.text_table, item:draw(i))
    end
    mp.set_osd_ass(self.canvas_width, self.canvas_height, table.concat(self.text_table, "\n"))
end

function Menu:erase()
    mp.set_osd_ass(self.canvas_width, self.canvas_height, '')
end

function Menu:up()
    local before_idx, before_item = self.selected, self:get_selected_item()
    while self.selected > 1 do
        self.selected = self.selected - 1
        local item = self:get_selected_item()
        if item:is_selectable() then
            item:on_selected_cb()
            item.is_selected = true
            before_item.is_selected = false
            return self:draw()
        end
    end
    self.selected = before_idx
    before_item.is_selected = true
end

function Menu:down()
    local count = #self.options + #self.choices
    local before_idx, before_item = self.selected, self:get_selected_item()
    while self.selected < count do
        self.selected = self.selected + 1
        local item = self:get_selected_item()
        if item:is_selectable() then
            item:on_selected_cb()
            item.is_selected = true
            before_item.is_selected = false
            return self:draw()
        end
    end
    self.selected = before_idx
    before_item.is_selected = true
end

function Menu:get_selected_item()
    return self.options[self.selected] or self.choices[self.selected - #self.options]
end

function Menu:act()
    self:close()
    self:get_selected_item():on_chosen_cb()
end

function Menu:get_keybindings()
    local bindings = {
        { key = 'h', fn = function() self:close() end },
        { key = 'j', fn = function() self:down() end },
        { key = 'k', fn = function() self:up() end },
        { key = 'l', fn = function() self:act() end },
        { key = 'down', fn = function() self:down() end },
        { key = 'up', fn = function() self:up() end },
        { key = 'Enter', fn = function() self:act() end },
        { key = 'ESC', fn = function() self:close() end },
        { key = 'n', fn = function() self:close() end },
    }
    if self.on_search then
        table.insert(bindings, { key = '/', fn = function() self:on_search() end })
    end
    return bindings
end

function Menu:open()
    self.selected = self.selected or 1
    self:get_selected_item().is_selected = true
    for _, val in pairs(self:get_keybindings()) do
        mp.add_forced_key_binding(val.key, val.key, val.fn)
    end
    self:draw()
end

-- Unbind menu keys without triggering close callbacks or erasing OSD.
-- Use before opening mp.input to avoid keybinding conflicts.
function Menu:suspend()
    for _, val in pairs(self:get_keybindings()) do
        mp.remove_key_binding(val.key)
    end
end

-- Rebind menu keys after suspend. Call when mp.input closes.
function Menu:resume()
    for _, val in pairs(self:get_keybindings()) do
        mp.add_forced_key_binding(val.key, val.key, val.fn)
    end
    self:draw()
end

-- Move selection to first visible+selectable item if current selection is invalid.
function Menu:reanchor_selection()
    local current = self:get_selected_item()
    if current and current:is_selectable() then return end
    -- Try options first
    for i, opt in ipairs(self.options) do
        if opt:is_selectable() then
            if current then current.is_selected = false end
            self.selected = i
            opt.is_selected = true
            return
        end
    end
    -- Then choices
    for i, choice in ipairs(self.choices) do
        if choice:is_selectable() then
            if current then current.is_selected = false end
            self.selected = #self.options + i
            choice.is_selected = true
            return
        end
    end
end

function Menu:close()
    for _, val in pairs(self:get_keybindings()) do
        mp.remove_key_binding(val.key)
    end
    for _, callback in ipairs(self.on_close_callbacks) do
        callback(self)
    end
    self:erase()
end

return Menu
