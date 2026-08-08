#!/usr/bin/env python3

import json
import sys
from pathlib import Path


def clamp(value: float) -> int:
    return max(0, min(255, round(value)))


def normalize_hex(value: str) -> str:
    text = value.strip()
    if not text.startswith("#"):
        text = f"#{text}"
    if len(text) == 4:
        text = "#" + "".join(ch * 2 for ch in text[1:])
    if len(text) != 7:
        raise ValueError(f"Unsupported color value: {value}")
    return text.lower()


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = normalize_hex(value)
    return tuple(int(value[index:index + 2], 16) for index in (1, 3, 5))


def rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    return "#{:02x}{:02x}{:02x}".format(*rgb)


def with_alpha(value: str, alpha: int) -> str:
    return "#{:02x}{}".format(clamp(alpha), normalize_hex(value)[1:])


def mix(left: str, right: str, amount: float) -> str:
    lrgb = hex_to_rgb(left)
    rrgb = hex_to_rgb(right)
    mixed = tuple(clamp(l + (r - l) * amount) for l, r in zip(lrgb, rrgb))
    return rgb_to_hex(mixed)


def brighten(value: str, amount: float) -> str:
    return mix(value, "#ffffff", amount)


def darken(value: str, amount: float) -> str:
    return mix(value, "#000000", amount)


def hex_to_rgb_tuple(value: str) -> tuple[int, int, int]:
    return hex_to_rgb(value)


def hex_to_rgba_tuple(value: str) -> tuple[int, int, int, float]:
    text = value.strip().lower()
    if text.startswith("#"):
        text = text[1:]
    if len(text) == 6:
        text = f"{text}ff"
    if len(text) != 8:
        raise ValueError(f"Unsupported RGBA value: {value}")
    alpha = int(text[0:2], 16) / 255.0
    red = int(text[2:4], 16)
    green = int(text[4:6], 16)
    blue = int(text[6:8], 16)
    return red, green, blue, alpha


def fmt_rgb(value: str) -> str:
    red, green, blue = hex_to_rgb_tuple(value)
    return f"rgb({red},{green},{blue})"


def fmt_rgba(value: str) -> str:
    red, green, blue, alpha = hex_to_rgba_tuple(value)
    return f"rgba({red},{green},{blue},{alpha:.3f})"


def strip_hash(value: str) -> str:
    return normalize_hex(value)[1:]


def build_theme(payload: dict) -> dict:
    special = payload.get("special", {})
    colors = payload.get("colors", {})

    background = special.get("background", "#101820")
    foreground = special.get("foreground", "#f3fbff")
    accent = colors.get("color6") or colors.get("color4") or "#7ae7d7"
    accent_warm = colors.get("color3") or colors.get("color1") or "#ffbf7a"
    danger = colors.get("color1") or colors.get("color9") or "#ff6b81"

    dark_surface = darken(background, 0.24)
    dark_control = darken(background, 0.36)
    rail_top_base = mix(background, accent, 0.18)
    rail_bottom_base = mix(background, dark_surface, 0.42)
    card_base = brighten(background, 0.14)
    border_base = mix(foreground, accent, 0.18)
    workspace_active_text = darken(brighten(accent, 0.45), 0.74)

    return {
        "railTop": with_alpha(rail_top_base, 0xEE),
        "railBottom": with_alpha(rail_bottom_base, 0xDD),
        "panelShadow": "#22000000",
        "cardColor": with_alpha(card_base, 0x22),
        "cardBorder": with_alpha(border_base, 0x36),
        "mutedText": with_alpha(foreground, 0x99),
        "bodyText": with_alpha(brighten(foreground, 0.04), 0xDF),
        "primaryText": with_alpha(brighten(foreground, 0.08), 0xF3),
        "titleText": with_alpha(brighten(foreground, 0.1), 0xF5),
        "brightText": with_alpha(brighten(foreground, 0.14), 0xE8),
        "accent": normalize_hex(accent),
        "accentWarm": normalize_hex(accent_warm),
        "darkControl": dark_control,
        "darkSurface": dark_surface,
        "hoverOverlay": with_alpha(foreground, 0x24),
        "workspaceHoverFill": with_alpha(accent, 0x1F),
        "workspaceActiveBorder": with_alpha(dark_surface, 0xCC),
        "workspaceHoverBorder": with_alpha(brighten(accent, 0.55), 0x5A),
        "workspaceIdleBorder": with_alpha(accent, 0x42),
        "workspaceActiveText": workspace_active_text,
        "dangerText": normalize_hex(danger),
        "attentionBorder": with_alpha(accent_warm, 0x66),
        "attentionTint": with_alpha(brighten(accent_warm, 0.28), 0x55),
        "attentionFill": with_alpha(accent_warm, 0x33),
        "warmBorder": with_alpha(brighten(accent_warm, 0.45), 0x55),
        "softBorder": with_alpha(foreground, 0x4D),
        "faintBorder": with_alpha(foreground, 0x1C),
        "subtleLine": with_alpha(foreground, 0x42),
    }


def build_theme_for_mode(payload: dict, mode: str) -> dict:
    special = payload.get("special", {})
    colors = payload.get("colors", {})

    background = special.get("background", "#101820")
    foreground = special.get("foreground", "#f3fbff")
    accent = colors.get("color6") or colors.get("color4") or "#7ae7d7"
    accent_warm = colors.get("color3") or colors.get("color1") or "#ffbf7a"
    danger = colors.get("color1") or colors.get("color9") or "#ff6b81"

    if mode == "light":
        panel_shadow = "#18000000"
        surface = darken(background, 0.04)
        control = darken(background, 0.08)
        rail_top_base = mix(background, accent, 0.08)
        rail_bottom_base = mix(background, control, 0.18)
        card_base = brighten(background, 0.02)
        border_base = mix(foreground, accent, 0.08)
        workspace_active_text = darken(accent, 0.72)

        return {
            "railTop": with_alpha(rail_top_base, 0xF2),
            "railBottom": with_alpha(rail_bottom_base, 0xEE),
            "panelShadow": panel_shadow,
            "cardColor": with_alpha(card_base, 0xE8),
            "cardBorder": with_alpha(border_base, 0x44),
            "mutedText": with_alpha(foreground, 0xB8),
            "bodyText": with_alpha(darken(foreground, 0.04), 0xE4),
            "primaryText": with_alpha(darken(foreground, 0.10), 0xF4),
            "titleText": with_alpha(darken(foreground, 0.12), 0xF8),
            "brightText": with_alpha(darken(foreground, 0.16), 0xF8),
            "accent": normalize_hex(accent),
            "accentWarm": normalize_hex(accent_warm),
            "darkControl": control,
            "darkSurface": surface,
            "hoverOverlay": with_alpha(darken(foreground, 0.20), 0x12),
            "workspaceHoverFill": with_alpha(accent, 0x22),
            "workspaceActiveBorder": with_alpha(darken(accent, 0.44), 0xA8),
            "workspaceHoverBorder": with_alpha(accent, 0x68),
            "workspaceIdleBorder": with_alpha(accent, 0x50),
            "workspaceActiveText": workspace_active_text,
            "dangerText": normalize_hex(danger),
            "attentionBorder": with_alpha(accent_warm, 0x72),
            "attentionTint": with_alpha(brighten(accent_warm, 0.12), 0x66),
            "attentionFill": with_alpha(accent_warm, 0x24),
            "warmBorder": with_alpha(brighten(accent_warm, 0.22), 0x62),
            "softBorder": with_alpha(foreground, 0x42),
            "faintBorder": with_alpha(foreground, 0x20),
            "subtleLine": with_alpha(foreground, 0x34),
        }

    return build_theme(payload)


def build_hyprland_colors(theme: dict) -> str:
    active_start = fmt_rgba(with_alpha(brighten(theme["accent"], 0.08), 0xF2))
    active_end = fmt_rgba(with_alpha(brighten(theme["accentWarm"], 0.06), 0xCC))
    inactive = fmt_rgba(with_alpha(darken(theme["accent"], 0.42), 0x42))
    shadow = fmt_rgba(with_alpha(theme["darkSurface"], 0xCC))

    return "\n".join([
        "general:col.active_border = " + f"{active_start} {active_end} 45deg",
        "general:col.inactive_border = " + inactive,
        "decoration:shadow:color = " + shadow,
        "",
    ])


def build_hyprland_lua(theme: dict) -> str:
    active_start = fmt_rgba(with_alpha(brighten(theme["accent"], 0.08), 0xF2))
    active_end = fmt_rgba(with_alpha(brighten(theme["accentWarm"], 0.06), 0xCC))
    inactive = fmt_rgba(with_alpha(darken(theme["accent"], 0.42), 0x42))
    shadow = fmt_rgba(with_alpha(theme["darkSurface"], 0xCC))

    return "\n".join([
        "return {",
        "  general = {",
        "    col = {",
        '      active_border = { colors = {'
        + json.dumps(active_start)
        + ", "
        + json.dumps(active_end)
        + '}, angle = 45 },',
        f"      inactive_border = {json.dumps(inactive)},",
        "    },",
        "  },",
        "  decoration = {",
        "    shadow = {",
        f"      color = {json.dumps(shadow)},",
        "    },",
        "  },",
        "}",
        "",
    ])


def build_hyprlock_colors(theme: dict) -> str:
    background = fmt_rgba(with_alpha(theme["darkSurface"], 0xD9))
    input_outer = fmt_rgb(theme["accent"])
    input_inner = fmt_rgba(with_alpha(theme["cardColor"][3:] if theme["cardColor"].startswith("#") and len(theme["cardColor"]) == 9 else theme["darkControl"], 0xF0))
    input_font = fmt_rgb(brighten(theme["primaryText"][3:] if theme["primaryText"].startswith("#") and len(theme["primaryText"]) == 9 else theme["primaryText"], 0.02))
    label = fmt_rgba(with_alpha(theme["brightText"][3:] if theme["brightText"].startswith("#") and len(theme["brightText"]) == 9 else theme["brightText"], 0xF5))

    return "\n".join([
        f"$lock_background = {background}",
        f"$lock_input_outer = {input_outer}",
        f"$lock_input_inner = {input_inner}",
        f"$lock_input_font = {input_font}",
        f"$lock_label = {label}",
        "",
    ])


def build_rofi_theme(theme: dict) -> str:
    base = theme["darkSurface"]
    surface = theme["darkControl"]
    card = theme["cardColor"]
    border = theme["cardBorder"]
    accent = theme["accent"]
    accent_warm = theme["accentWarm"]
    foreground = theme["primaryText"]
    muted = theme["mutedText"]

    return "\n".join([
        "* {",
        f"    background: {base};",
        f"    background-alt: {surface};",
        f"    foreground: {foreground};",
        f"    foreground-muted: {muted};",
        f"    selected: {accent};",
        f"    selected-alt: {accent_warm};",
        f"    active: {accent};",
        f"    urgent: {accent_warm};",
        f"    border-color: {border};",
        f"    card-color: {card};",
        "}",
        "",
    ])


def build_kitty_theme(payload: dict, theme: dict) -> str:
    special = payload.get("special", {})
    colors = payload.get("colors", {})
    mode = theme.get("mode", "dark")

    foreground = special.get("foreground", "#f3fbff")
    background = special.get("background", "#101820")
    cursor = special.get("cursor", foreground)
    selection_background = colors.get("color7", foreground)

    if mode == "light":
        background = brighten(background, 0.04)
        foreground = darken(background, 0.84)
        cursor = foreground
        selection_background = brighten(theme["accent"], 0.38)

    lines = [
        f"foreground {foreground}",
        f"background {background}",
        f"cursor {cursor}",
        f"selection_foreground {background}",
        f"selection_background {selection_background}",
        f"active_border_color {theme['accent']}",
        f"inactive_border_color {darken(theme['accent'], 0.32)}",
        f"active_tab_background {theme['accentWarm']}",
        f"active_tab_foreground {background}",
        f"inactive_tab_background {theme['darkSurface']}",
        f"inactive_tab_foreground {foreground}",
        f"tab_bar_background {theme['darkControl']}",
        "",
    ]

    for index in range(16):
        fallback = special.get("foreground", "#f3fbff") if index == 7 or index == 15 else special.get("background", "#101820")
        lines.append(f"color{index} {colors.get(f'color{index}', fallback)}")

    lines.append("")
    return "\n".join(lines)


def build_caelestia_colours(payload: dict, theme: dict) -> dict:
    special = payload.get("special", {})
    colors = payload.get("colors", {})
    mode = theme.get("mode", "dark")

    background = normalize_hex(special.get("background", "#101820"))
    foreground = normalize_hex(special.get("foreground", "#f3fbff"))
    accent = normalize_hex(theme["accent"])
    accent_warm = normalize_hex(theme["accentWarm"])
    danger = normalize_hex(theme["dangerText"])

    if mode == "light":
        surface = brighten(background, 0.05)
        surface_dim = darken(background, 0.06)
        surface_bright = brighten(background, 0.12)
        on_surface = foreground
        on_surface_variant = mix(foreground, background, 0.28)
        outline = mix(foreground, background, 0.48)
        outline_variant = mix(foreground, background, 0.70)
    else:
        surface = background
        surface_dim = darken(background, 0.20)
        surface_bright = brighten(background, 0.14)
        on_surface = foreground
        on_surface_variant = mix(foreground, background, 0.24)
        outline = mix(foreground, background, 0.52)
        outline_variant = mix(foreground, background, 0.72)

    surface_container_lowest = darken(surface, 0.18) if mode == "dark" else brighten(surface, 0.06)
    surface_container_low = mix(surface, foreground, 0.06 if mode == "dark" else 0.03)
    surface_container = mix(surface, foreground, 0.10 if mode == "dark" else 0.05)
    surface_container_high = mix(surface, foreground, 0.15 if mode == "dark" else 0.08)
    surface_container_highest = mix(surface, foreground, 0.20 if mode == "dark" else 0.12)
    secondary = normalize_hex(colors.get("color4") or accent)
    tertiary = normalize_hex(colors.get("color5") or accent_warm)

    roles = {
        "rosewater": colors.get("color15", foreground),
        "flamingo": colors.get("color13", accent_warm),
        "pink": colors.get("color13", accent_warm),
        "mauve": colors.get("color5", tertiary),
        "red": colors.get("color1", danger),
        "maroon": colors.get("color9", danger),
        "peach": colors.get("color3", accent_warm),
        "yellow": colors.get("color11", accent_warm),
        "green": colors.get("color2", accent),
        "teal": colors.get("color6", accent),
        "sky": colors.get("color14", accent),
        "sapphire": colors.get("color12", secondary),
        "blue": colors.get("color4", secondary),
        "lavender": colors.get("color5", tertiary),
        "primary_paletteKeyColor": accent,
        "secondary_paletteKeyColor": secondary,
        "tertiary_paletteKeyColor": tertiary,
        "neutral_paletteKeyColor": surface,
        "neutral_variant_paletteKeyColor": surface_container,
        "background": background,
        "onBackground": on_surface,
        "surface": surface,
        "surfaceDim": surface_dim,
        "surfaceBright": surface_bright,
        "surfaceContainerLowest": surface_container_lowest,
        "surfaceContainerLow": surface_container_low,
        "surfaceContainer": surface_container,
        "surfaceContainerHigh": surface_container_high,
        "surfaceContainerHighest": surface_container_highest,
        "onSurface": on_surface,
        "surfaceVariant": surface_container_high,
        "onSurfaceVariant": on_surface_variant,
        "inverseSurface": foreground,
        "inverseOnSurface": background,
        "outline": outline,
        "outlineVariant": outline_variant,
        "shadow": "#000000",
        "scrim": "#000000",
        "surfaceTint": accent,
        "primary": accent,
        "onPrimary": background if mode == "dark" else foreground,
        "primaryContainer": mix(surface, accent, 0.28),
        "onPrimaryContainer": foreground,
        "inversePrimary": brighten(accent, 0.20) if mode == "dark" else darken(accent, 0.20),
        "secondary": secondary,
        "onSecondary": background if mode == "dark" else foreground,
        "secondaryContainer": mix(surface, secondary, 0.24),
        "onSecondaryContainer": foreground,
        "tertiary": tertiary,
        "onTertiary": background if mode == "dark" else foreground,
        "tertiaryContainer": mix(surface, tertiary, 0.24),
        "onTertiaryContainer": foreground,
        "error": danger,
        "onError": background if mode == "dark" else foreground,
        "errorContainer": mix(surface, danger, 0.25),
        "onErrorContainer": foreground,
        "primaryFixed": brighten(accent, 0.30),
        "primaryFixedDim": brighten(accent, 0.18),
        "onPrimaryFixed": darken(accent, 0.72),
        "onPrimaryFixedVariant": darken(accent, 0.52),
        "secondaryFixed": brighten(secondary, 0.30),
        "secondaryFixedDim": brighten(secondary, 0.18),
        "onSecondaryFixed": darken(secondary, 0.72),
        "onSecondaryFixedVariant": darken(secondary, 0.52),
        "tertiaryFixed": brighten(tertiary, 0.30),
        "tertiaryFixedDim": brighten(tertiary, 0.18),
        "onTertiaryFixed": darken(tertiary, 0.72),
        "onTertiaryFixedVariant": darken(tertiary, 0.52),
    }

    return {key: strip_hash(value) for key, value in roles.items()}


def build_caelestia_scheme(payload: dict, theme: dict) -> dict:
    return {
        "name": "zetshell",
        "flavour": "wallpaper",
        "mode": theme.get("mode", "dark"),
        "variant": "dynamic",
        "colours": build_caelestia_colours(payload, theme),
    }


def build_vesktop_theme(scheme: dict) -> str:
    colours = scheme["colours"]

    def css(name: str) -> str:
        return f"#{colours[name]}"

    return "\n".join([
        "/**",
        " * @name Zetshell Dynamic",
        " * @author zetshell",
        " * @description Generated from the current wallpaper palette.",
        "*/",
        "",
        ":root {",
        f"    --background-primary: {css('surface')};",
        f"    --background-secondary: {css('surfaceContainerLow')};",
        f"    --background-secondary-alt: {css('surfaceContainer')};",
        f"    --background-tertiary: {css('surfaceDim')};",
        f"    --background-accent: {css('primary')};",
        f"    --background-floating: {css('surfaceContainerHigh')};",
        f"    --channeltextarea-background: {css('surfaceContainer')};",
        f"    --modal-background: {css('surfaceContainer')};",
        f"    --modal-footer-background: {css('surfaceContainerLow')};",
        f"    --text-normal: {css('onSurface')};",
        f"    --text-muted: {css('onSurfaceVariant')};",
        f"    --header-primary: {css('onSurface')};",
        f"    --header-secondary: {css('onSurfaceVariant')};",
        f"    --interactive-normal: {css('onSurfaceVariant')};",
        f"    --interactive-hover: {css('onSurface')};",
        f"    --interactive-active: {css('primary')};",
        f"    --interactive-muted: {css('outline')};",
        f"    --brand-experiment: {css('primary')};",
        f"    --brand-experiment-560: {css('primary')};",
        f"    --button-secondary-background: {css('surfaceContainerHigh')};",
        f"    --button-secondary-background-hover: {css('surfaceContainerHighest')};",
        f"    --button-danger-background: {css('error')};",
        f"    --input-background: {css('surfaceContainerLow')};",
        f"    --background-modifier-hover: color-mix(in srgb, {css('primary')}, transparent 86%);",
        f"    --background-modifier-selected: color-mix(in srgb, {css('primary')}, transparent 74%);",
        f"    --background-modifier-active: color-mix(in srgb, {css('primary')}, transparent 68%);",
        f"    --background-mentioned: color-mix(in srgb, {css('tertiary')}, transparent 84%);",
        f"    --background-mentioned-hover: color-mix(in srgb, {css('tertiary')}, transparent 78%);",
        f"    --scrollbar-thin-thumb: {css('outline')};",
        f"    --scrollbar-auto-thumb: {css('outline')};",
        f"    --scrollbar-auto-track: {css('surfaceContainerLow')};",
        "}",
        "",
    ])


def build_spicetify_theme(scheme: dict) -> str:
    colours = scheme["colours"]

    return "\n".join([
        "[zetshell]",
        f"text               = {colours['onSurface']}",
        f"subtext            = {colours['onSurfaceVariant']}",
        f"main               = {colours['surface']}",
        f"sidebar            = {colours['surfaceDim']}",
        f"player             = {colours['surfaceContainerLow']}",
        f"card               = {colours['surfaceContainer']}",
        f"shadow             = {colours['shadow']}",
        f"selected-row       = {colours['onSurface']}",
        f"button             = {colours['primary']}",
        f"button-active      = {colours['primaryFixed']}",
        f"button-disabled    = {colours['outline']}",
        f"tab-active         = {colours['surfaceContainerHigh']}",
        f"notification       = {colours['primaryContainer']}",
        f"notification-error = {colours['errorContainer']}",
        f"misc               = {colours['outlineVariant']}",
        "",
    ])


def write_caelestia_scheme(scheme: dict) -> None:
    state_dir = Path.home() / ".local" / "state" / "caelestia"
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "scheme.json").write_text(json.dumps(scheme, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_vesktop_theme(scheme: dict) -> None:
    target = Path.home() / ".config" / "vesktop" / "themes" / "zetshell.theme.css"
    target.parent.mkdir(parents=True, exist_ok=True)
    theme = build_vesktop_theme(scheme)
    target.write_text(theme, encoding="utf-8")

    quick_css = Path.home() / ".config" / "vesktop" / "settings" / "quickCss.css"
    quick_css.parent.mkdir(parents=True, exist_ok=True)
    quick_css.write_text(theme, encoding="utf-8")


def write_spicetify_theme(scheme: dict) -> None:
    target = Path.home() / ".config" / "spicetify" / "Themes" / "zetshell" / "color.ini"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(build_spicetify_theme(scheme), encoding="utf-8")


def main() -> int:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / ".cache" / "wal" / "colors.json"
    target = Path(sys.argv[2]) if len(sys.argv) > 2 else Path.home() / ".local" / "state" / "zetshell" / "theme.json"
    mode = sys.argv[3] if len(sys.argv) > 3 else "dark"

    data = json.loads(source.read_text(encoding="utf-8"))
    theme = build_theme_for_mode(data, mode)
    theme["mode"] = mode

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(theme, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (target.parent / "hyprland-colors.conf").write_text(build_hyprland_colors(theme), encoding="utf-8")
    (target.parent / "hyprland-colors.lua").write_text(build_hyprland_lua(theme), encoding="utf-8")
    (target.parent / "hyprlock-colors.conf").write_text(build_hyprlock_colors(theme), encoding="utf-8")
    (target.parent / "rofi-theme.rasi").write_text(build_rofi_theme(theme), encoding="utf-8")
    (target.parent / "kitty-theme.conf").write_text(build_kitty_theme(data, theme), encoding="utf-8")

    scheme = build_caelestia_scheme(data, theme)
    write_caelestia_scheme(scheme)
    write_vesktop_theme(scheme)
    write_spicetify_theme(scheme)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
