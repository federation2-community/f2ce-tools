-- Adjustable Border Containers System for Mudlet
-- Using percentages to avoid window resize issues

-- Track previous positions for detecting edge movements
local previous_state = {}

-- Base percentage configuration
UI.container_config = {
    left_width_pct        = 20,
    right_width_pct       = 20,
    top_left_center_ratio      = 0.93,  -- 93% of center space
    top_left_height_pct        = 5,
    top_right_height_pct       = 7,
    cargo_width_pct            = 15,
    local_players_width_pct    = 10
}

-- Helper to convert pixels and percentages
function ui_convert_dimension(val, dim, to_unit)
    local w, h = getMainWindowSize()
    -- Determine if we are working with Width or Height
    local total = (dim == "width" or dim == "w") and w or h
    
    if to_unit == "px" or to_unit == "pixel" then
        -- Percentage to Pixels: floor it since pixels must be integers
        return math.floor(total * (val / 100))
    elseif to_unit == "pct" or to_unit == "percent" then
        -- Pixels to Percentage
        return (val / total) * 100
    else
        debugc("ui_convert_dimension: Invalid unit type. Use 'px' or 'pct'.")
        return nil
    end
end

-- Store current state for comparison
local function ui_capture_state()
    if not UI.top_left_frame or not UI.top_right_frame then return end
    
    local screen_width = getMainWindowSize()
    
    previous_state = {
        top_left_x_pct      = ui_convert_dimension(UI.top_left_frame:get_x(),      "w", "pct"),
        top_left_width_pct  = ui_convert_dimension(UI.top_left_frame:get_width(),  "w", "pct"),
        top_right_x_pct     = ui_convert_dimension(UI.top_right_frame:get_x(),     "w", "pct"),
        top_right_width_pct = ui_convert_dimension(UI.top_right_frame:get_width(), "w", "pct")
    }
end

-- Create all containers
function ui_create_containers()
    local screen_width, screen_height = getMainWindowSize()
    
    local left_width_pct  = UI.container_config.left_width_pct
    local right_width_pct = UI.container_config.right_width_pct
    
    -- Calculate center space percentages
    local available_center_pct = 100 - left_width_pct - right_width_pct
    local top_left_width_pct   = available_center_pct * UI.container_config.top_left_center_ratio
    local top_right_width_pct  = available_center_pct - top_left_width_pct
    
    local top_left_height_pct  = UI.container_config.top_left_height_pct
    local top_right_height_pct = UI.container_config.top_right_height_pct
    local top_height_diff_pct  = top_right_height_pct - top_left_height_pct
    
    local cargo_width_pct = UI.container_config.cargo_width_pct
   
    -- Create Left Container (attached to left border)
    UI.left_frame = Adjustable.Container:new({
        name          = "UI.left_frame",
        x             = 0,
        y             = 0,
        width         = left_width_pct .. "%",
        height        = "100%",
        lockStyle     = "border",
        adjLabelstyle = UI.style.frame_css,
        attached      = "left",
        autoSave      = false,
        autoLoad      = false
    })
    UI.left_frame:connectToBorder("left")
    UI.left_frame:lockContainer("border")
    f2t_ui_register_container("UI.left_frame", UI.left_frame)

    -- Create Right Container (attached to right border)
    UI.right_frame = Adjustable.Container:new({
        name          = "UI.right_frame",
        x             = (100 - right_width_pct) .. "%",
        y             = 0,
        width         = right_width_pct .. "%",
        height        = "100%",
        lockStyle     = "border",
        adjLabelstyle = UI.style.frame_css,
        attached      = "right",
        autoSave      = false,
        autoLoad      = false
    })
    UI.right_frame:connectToBorder("right")
    UI.right_frame:lockContainer("border")
    f2t_ui_register_container("UI.right_frame", UI.right_frame)

    -- Create Top Left Container (attached to top and left borders)
    UI.top_left_frame = Adjustable.Container:new({
        name          = "UI.top_left_frame",
        x             = left_width_pct .. "%",
        y             = 0,
        width         = top_left_width_pct  .. "%",
        height        = top_left_height_pct .. "%",
        lockStyle     = "border",
        adjLabelstyle = UI.style.frame_css,
        attached      = "top",
        autoSave      = false,
        autoLoad      = false
    })
    UI.top_left_frame:lockContainer("border")
    f2t_ui_register_container("UI.top_left_frame", UI.top_left_frame)

    -- Create Top Right Container (attached to top and right borders)
    UI.top_right_frame = Adjustable.Container:new({
        name          = "UI.top_right_frame",
        x             = (left_width_pct + top_left_width_pct) .. "%",
        y             = 0,
        width         = top_right_width_pct  .. "%",
        height        = top_right_height_pct .. "%",
        lockStyle     = "border",
        adjLabelstyle = UI.style.frame_css,
        attached      = "top",
        noLimit       = false,
        autoSave      = false,
        autoLoad      = false
    })
    UI.top_right_frame:lockContainer("border")
    f2t_ui_register_container("UI.top_right_frame", UI.top_right_frame)

    -- Calculate cargo position (to the left of right_frame)
    local cargo_x_pct              = 100 - right_width_pct - cargo_width_pct
    local local_players_width_pct  = UI.container_config.local_players_width_pct
    local local_players_x_pct      = cargo_x_pct - local_players_width_pct

    -- Local players: initially placed in standalone position (flush against right frame).
    -- ui_refresh_local_players_layout() relocates it whenever cargo visibility changes.
    local lp_standalone_x_pct = 100 - right_width_pct - local_players_width_pct

    -- Use Geyser.Label so move() and resize() work reliably while visible.
    -- CSS is swapped at runtime (standalone vs with-cargo) via setStyleSheet().
    UI.local_players_dropdown = Geyser.Label:new({
        name    = "UI.local_players_dropdown",
        x       = lp_standalone_x_pct .. "%",
        y       = top_right_height_pct .. "%",
        width   = local_players_width_pct .. "%",
        height  = "20%",
        message = "",
    })
    UI.local_players_dropdown:setStyleSheet(UI.style.local_players_dropdown_standalone_css)
    UI.local_players_dropdown:hide()
    f2t_ui_register_container("UI.local_players_dropdown", UI.local_players_dropdown)

    -- Right-edge border strip: shown only when LP extends below cargo's bottom.
    -- Width is 2px matching the other panel borders; height and position are set dynamically.
    UI.lp_overflow_border = Geyser.Label:new({
        name   = "UI.lp_overflow_border",
        x      = "0%",
        y      = "0%",
        width  = 2,
        height = 0,
    })
    UI.lp_overflow_border:setStyleSheet([[
        border-left: 2px solid rgba(255,255,255,0.46);
        background: transparent;
    ]])
    UI.lp_overflow_border:hide()
    f2t_ui_register_container("UI.lp_overflow_border", UI.lp_overflow_border)

    -- Gap filler for standalone mode: fills the height gap left by top_right_frame
    UI.local_players_gap_filler = Geyser.Label:new({
        name    = "UI.local_players_gap_filler",
        x       = lp_standalone_x_pct                         .. "%",
        y       = top_left_height_pct                         .. "%",
        width   = (local_players_width_pct - top_right_width_pct) .. "%",
        height  = top_height_diff_pct                         .. "%",
        message = "<center><white><b>Local Players:</b></white></center>"
    })
    UI.local_players_gap_filler:setStyleSheet(UI.style.local_players_gap_filler_css)
    UI.local_players_gap_filler:hide()
    f2t_ui_register_container("UI.local_players_gap_filler", UI.local_players_gap_filler)

    -- Gap filler - seamless top section with label
    UI.cargo_gap_filler = Geyser.Label:new({
        name    = "UI.cargo_gap_filler",
        x       = cargo_x_pct                             .. "%",
        y       = top_left_height_pct                     .. "%",
        width   = (cargo_width_pct - top_right_width_pct) .. "%",
        height  = top_height_diff_pct                     .. "%",
        message = "<center><dim_grey><b>Hold Contents:</b></dim_grey></center>"
    })
    UI.cargo_gap_filler:setStyleSheet(UI.style.cargo_gap_filler_css)
    UI.cargo_gap_filler:hide()
    f2t_ui_register_container("UI.cargo_gap_filler", UI.cargo_gap_filler)

    -- Create the cargo dropdown container
    UI.cargo_dropdown = Adjustable.Container:new({
        name          = "UI.cargo_dropdown",
        x             = cargo_x_pct          .. "%",
        y             = top_right_height_pct .. "%",
        width         = cargo_width_pct      .. "%",
        height        = "20%",  -- Initial height
        lockStyle     = "border",
        adjLabelstyle = UI.style.cargo_dropdown_css,
        autoSave      = false,
        autoLoad      = false
    })
    UI.cargo_dropdown:lockContainer("border")
    UI.cargo_dropdown:hide()
    f2t_ui_register_container("UI.cargo_dropdown", UI.cargo_dropdown)

    -- Capture initial state
    tempTimer(0.1, ui_capture_state)

    -- Enable Adjustable Containers (Tabs)
    Adjustable.Container:doAll(function(self) self:addConnectMenu() end)
end

-- Register event handlers to sync container sizes when one is resized
function ui_on_container_reposition(event, container_name)
    if not container_name then return end

    local screen_width = getMainWindowSize()

    -- Get current percentage values
    local left_width_pct  = ui_convert_dimension(UI.left_frame:get_width(),  "w", "pct")
    local right_width_pct = ui_convert_dimension(UI.right_frame:get_width(), "w", "pct")
    local available_pct   = 100 - left_width_pct - right_width_pct

    -- Helper to update cargo and local players position
    local function update_cargo_position()
        if UI.cargo_gap_filler and UI.cargo_dropdown then
            local cargo_width_pct = ui_convert_dimension(UI.cargo_dropdown:get_width(), "w", "pct")
            local cargo_x_pct     = 100 - right_width_pct - cargo_width_pct

            local top_left_height_pct  = ui_convert_dimension(UI.top_left_frame:get_height(),  "h", "pct")
            local top_right_height_pct = ui_convert_dimension(UI.top_right_frame:get_height(), "h", "pct")
            local top_right_width_pct  = ui_convert_dimension(UI.top_right_frame:get_width(),  "w", "pct")
            local top_height_diff_pct  = top_right_height_pct - top_left_height_pct

            UI.cargo_gap_filler:move(cargo_x_pct .. "%", top_left_height_pct .. "%")
            UI.cargo_gap_filler:resize((cargo_width_pct - top_right_width_pct) .. "%", top_height_diff_pct .. "%")

            UI.cargo_dropdown:move(cargo_x_pct .. "%", top_right_height_pct .. "%")

            -- Sync config with live container geometry before refreshing LP layout
            UI.container_config.left_width_pct       = left_width_pct
            UI.container_config.right_width_pct      = right_width_pct
            UI.container_config.top_left_height_pct  = top_left_height_pct
            UI.container_config.top_right_height_pct = top_right_height_pct
            local avail = 100 - left_width_pct - right_width_pct
            if avail > 0 then
                local tl_w = ui_convert_dimension(UI.top_left_frame:get_width(), "w", "pct")
                UI.container_config.top_left_center_ratio = tl_w / avail
            end

            if ui_update_local_players then ui_update_local_players() end
        end
    end

    -- When left container resizes
    if container_name == "UI.left_frame" then
        local top_left_width_pct  = ui_convert_dimension(UI.top_left_frame:get_width(),  "w", "pct")
        local top_right_width_pct = ui_convert_dimension(UI.top_right_frame:get_width(), "w", "pct")
        local total_top_pct       = top_left_width_pct + top_right_width_pct
        local ratio               = top_left_width_pct / total_top_pct

        UI.top_left_frame:move(left_width_pct .. "%", 0)
        UI.top_left_frame:resize((available_pct * ratio) .. "%", nil)

        local new_top_left_pct = ui_convert_dimension(UI.top_left_frame:get_width(), "w", "pct")

        UI.top_right_frame:move((left_width_pct + new_top_left_pct) .. "%", 0)
        UI.top_right_frame:resize((available_pct * (1 - ratio)) .. "%", nil)

        update_cargo_position()
    end

    -- When right container resizes
    if container_name == "UI.right_frame" then
        local top_left_width_pct  = ui_convert_dimension(UI.top_left_frame:get_width(),  "w", "pct")
        local top_right_width_pct = ui_convert_dimension(UI.top_right_frame:get_width(), "w", "pct")
        local total_top_pct       = top_left_width_pct + top_right_width_pct
        local ratio               = top_left_width_pct / total_top_pct

        UI.top_left_frame:resize((available_pct * ratio) .. "%", nil)

        local new_top_left_pct = ui_convert_dimension(UI.top_left_frame:get_width(), "w", "pct")

        UI.top_right_frame:move((left_width_pct + new_top_left_pct) .. "%", 0)
        UI.top_right_frame:resize((available_pct * (1 - ratio)) .. "%", nil)
        UI.right_frame:move((100 - right_width_pct) .. "%", 0)

        update_cargo_position()
    end

    -- When top left resizes
    if container_name == "UI.top_left_frame" then
        local current_x_pct     = ui_convert_dimension(UI.top_left_frame:get_x(),     "w", "pct")
        local current_width_pct = ui_convert_dimension(UI.top_left_frame:get_width(), "w", "pct")

        -- Detect edge movements
        local left_edge_moved  = previous_state.top_left_x_pct     and math.abs(current_x_pct - previous_state.top_left_x_pct) > 0.5
        local right_edge_moved = previous_state.top_left_width_pct and math.abs(current_width_pct - previous_state.top_left_width_pct) > 0.5

        if left_edge_moved and not right_edge_moved then
            -- Snap back to left frame
            UI.top_left_frame:move(left_width_pct .. "%", 0)

            local new_width_pct = current_x_pct + current_width_pct - left_width_pct

            UI.top_left_frame:resize(new_width_pct .. "%", nil)
        end

        local top_left_final_pct = ui_convert_dimension(UI.top_left_frame:get_width(), "w", "pct")

        UI.top_right_frame:move((left_width_pct + top_left_final_pct)  .. "%", 0)
        UI.top_right_frame:resize((available_pct - top_left_final_pct) .. "%", nil)

        update_cargo_position()
    end

    -- When top right resizes
    if container_name == "UI.top_right_frame" then
        local current_x_pct     = ui_convert_dimension(UI.top_right_frame:get_x(),     "w", "pct")
        local current_width_pct = ui_convert_dimension(UI.top_right_frame:get_width(), "w", "pct")

        -- Detect edge movements
        local right_edge_moved = previous_state.top_right_width_pct and math.abs(current_width_pct - previous_state.top_right_width_pct) > 0.5
        local left_edge_moved  = previous_state.top_right_x_pct     and math.abs(current_x_pct - previous_state.top_right_x_pct) > 0.5

        if right_edge_moved and not left_edge_moved then
            -- Snap to right frame
            local right_boundary_pct = 100 - right_width_pct
            UI.top_right_frame:move((right_boundary_pct - current_width_pct) .. "%", 0)
        end

        local top_right_final_pct = ui_convert_dimension(UI.top_right_frame:get_width(), "w", "pct")
        local top_right_x_pct     = ui_convert_dimension(UI.top_right_frame:get_x(),     "w", "pct")

        UI.top_left_frame:move(left_width_pct .. "%", 0)
        UI.top_left_frame:resize((available_pct - top_right_final_pct) .. "%", nil)

        local top_left_final_pct = ui_convert_dimension(UI.top_left_frame:get_width(), "w", "pct")

        UI.top_right_frame:move((left_width_pct + top_left_final_pct) .. "%", 0)
        
        update_cargo_position()
    end

    -- Update previous state
    ui_capture_state()

    -- Keep the gear icon at the correct corner
    if ui_reposition_gear_icon then ui_reposition_gear_icon() end
end

-- Handle window resize
function ui_on_window_resize()
    -- Update cargo position after resize
    if UI.cargo_gap_filler and UI.cargo_dropdown then
        local left_width_pct  = ui_convert_dimension(UI.left_frame:get_width(),     "w", "pct")
        local right_width_pct = ui_convert_dimension(UI.right_frame:get_width(),    "w", "pct")
        local cargo_width_pct = ui_convert_dimension(UI.cargo_dropdown:get_width(), "w", "pct")
        local cargo_x_pct     = 100 - right_width_pct - cargo_width_pct

        local top_left_height_pct  = ui_convert_dimension(UI.top_left_frame:get_height(),  "h", "pct")
        local top_right_height_pct = ui_convert_dimension(UI.top_right_frame:get_height(), "h", "pct")
        local top_right_width_pct  = ui_convert_dimension(UI.top_right_frame:get_width(),  "w", "pct")
        local top_height_diff_pct  = top_right_height_pct - top_left_height_pct

        UI.cargo_gap_filler:move(cargo_x_pct .. "%", top_left_height_pct .. "%")
        UI.cargo_gap_filler:resize((cargo_width_pct - top_right_width_pct) .. "%", top_height_diff_pct .. "%")

        UI.cargo_dropdown:move(cargo_x_pct .. "%", top_right_height_pct .. "%")

        -- Sync config with live container geometry before refreshing LP layout
        UI.container_config.left_width_pct       = left_width_pct
        UI.container_config.right_width_pct      = right_width_pct
        UI.container_config.top_left_height_pct  = top_left_height_pct
        UI.container_config.top_right_height_pct = top_right_height_pct
        local avail = 100 - left_width_pct - right_width_pct
        if avail > 0 then
            local tl_w = ui_convert_dimension(UI.top_left_frame:get_width(), "w", "pct")
            UI.container_config.top_left_center_ratio = tl_w / avail
        end

        if ui_update_local_players then ui_update_local_players() end
    end

    -- Keep the gear icon at the correct corner
    if ui_reposition_gear_icon then ui_reposition_gear_icon() end

    -- Update state after resize
    ui_capture_state()
end

-- Called from ui_cargo.lua show/hide and after any window reshape.
function ui_reposition_local_players()
    if ui_update_local_players then ui_update_local_players() end
end