local M = {}

function M.load_lua_overrides(path)
    local chunk, err = loadfile(path)
    if not chunk then
        return nil, err
    end

    local ok, config = pcall(chunk)
    if not ok then
        return nil, config
    end

    if type(config) ~= "table" then
        return nil, "generated theme did not return a table"
    end

    return config
end

return M
