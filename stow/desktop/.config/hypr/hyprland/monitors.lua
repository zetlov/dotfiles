local M = {}

function M.setup(settings)
    if settings.main_monitor == "" then
        hl.monitor({
            output = "",
            mode = "preferred",
            position = "auto",
            scale = 1,
        })
        return
    end

    hl.monitor({
        output = settings.main_monitor,
        mode = settings.main_monitor_mode,
        position = settings.main_monitor_position,
        scale = settings.main_monitor_scale,
    })

    if settings.sub_monitor ~= "" then
        hl.monitor({
            output = settings.sub_monitor,
            mode = settings.sub_monitor_mode,
            position = settings.sub_monitor_position,
            scale = settings.sub_monitor_scale,
        })
    end

    for workspace = 1, 12 do
        hl.workspace_rule({
            workspace = tostring(workspace),
            monitor = settings.main_monitor,
        })
    end

    if settings.sub_monitor ~= "" then
        hl.workspace_rule({
            workspace = "name:vert",
            monitor = settings.sub_monitor,
        })
    end
end

return M
