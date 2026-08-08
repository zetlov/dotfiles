local M = {}

function M.setup(settings)
    hl.env("XCURSOR_SIZE", "24")
    hl.env("HYPRCURSOR_SIZE", "24")
    hl.env("XDG_SESSION_TYPE", "wayland")
    if settings.nvidia then
        hl.env("LIBVA_DRIVER_NAME", "nvidia")
        hl.env("GBM_BACKEND", "nvidia-drm")
        hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
        hl.env("NVD_BACKEND", "direct")
    end
    hl.env("QTK_IM_MODULE", "fcitx5")
    hl.env("QT_IM_MODULE", "fcitx5")
    hl.env("XMODIFIERS", "@im=fcitx5")

    -- Permissions remain disabled to match the current setup.
    -- hl.config({
    --     ecosystem = {
    --         enforce_permissions = true,
    --     },
    -- })
    -- hl.permission({
    --     binary = "/usr/(bin|local/bin)/grim",
    --     type = "screencopy",
    --     mode = "allow",
    -- })
    -- hl.permission({
    --     binary = "/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland",
    --     type = "screencopy",
    --     mode = "allow",
    -- })
    -- hl.permission({
    --     binary = "/usr/(bin|local/bin)/hyprpm",
    --     type = "plugin",
    --     mode = "allow",
    -- })
end

return M
