#!/usr/bin/env bash
#
# add-i3-catppuccin.sh
# Adds i3 (tiling window manager) as an ADDITIONAL LightDM session,
# themed in Catppuccin Mocha, alongside your existing XFCE setup.
#
# Designed for Debian 13 (trixie). i3 4.24 in trixie supports native gaps,
# so no i3-gaps fork is required.
#
# This is a standalone add-on, separate from debian-postinstall-script.sh —
# it does NOT touch, remove, or reconfigure XFCE in any way. It's safe to
# run on its own at any point after your main setup, and it's self-
# contained: it (re)installs rofi/alacritty/flameshot defensively even
# though your main script likely already has them, so this works whether
# or not that script ran first.
#
# Usage:
#   chmod +x add-i3-catppuccin.sh
#   ./add-i3-catppuccin.sh
#
# Do NOT run this as root / with sudo. It calls sudo itself where needed.

set -euo pipefail

LOG_FILE="$HOME/add-i3-catppuccin.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

fail_trap() {
    local exit_code=$? line_no=$1
    log "ERROR: script failed at line ${line_no} (exit code ${exit_code}). See ${LOG_FILE} for details."
    exit "${exit_code}"
}
trap 'fail_trap $LINENO' ERR

if [[ "${EUID}" -eq 0 ]]; then
    echo "Don't run this as root/sudo. Run it as your normal user; it calls sudo itself." >&2
    exit 1
fi

apt_install() {
    local pkgs=("$@") to_install=()
    for pkg in "${pkgs[@]}"; do
        dpkg -s "$pkg" &>/dev/null || to_install+=("$pkg")
    done
    if [[ ${#to_install[@]} -gt 0 ]]; then
        log "Installing: ${to_install[*]}"
        sudo apt-get install -y "${to_install[@]}"
    else
        log "Already installed, skipping: ${pkgs[*]}"
    fi
}

backup_if_exists() {
    local path="$1"
    if [[ -e "$path" ]]; then
        local backup="${path}.bak.$(date '+%Y%m%d%H%M%S')"
        log "Backing up existing ${path} to ${backup}"
        mv "$path" "$backup"
    fi
}

: > "$LOG_FILE"
log "Starting i3 + Catppuccin setup."
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null & )

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------
log "Updating package index."
sudo apt-get update

log "Installing i3 and supporting tools."
# i3 (not i3-gaps): gap support has been built into mainline i3 since
# v4.22, so the separate i3-gaps fork package isn't needed on trixie.
apt_install i3 polybar picom feh i3lock dunst mate-polkit numlockx git
# These are also installed by the main XFCE script, but i3 should remain
# usable when this add-on is run by itself.
apt_install rofi alacritty flameshot xterm fonts-jetbrains-mono dbus-user-session

# nm-applet is optional: do not force NetworkManager onto a system that uses
# /etc/network/interfaces. If the applet is already installed, i3 will start it.
if command -v nm-applet >/dev/null 2>&1; then
    log "NetworkManager applet detected; it will be started in i3."
else
    log "NetworkManager applet not installed; i3 will start without it."
fi

# ---------------------------------------------------------------------------
# 2. Rofi theme (official Catppuccin Mocha .rasi, not packaged — cloned
#    from Catppuccin's own theme repo, same pattern as the icon themes in
#    the main script)
# ---------------------------------------------------------------------------
ROFI_THEME_DIR="$HOME/.config/rofi"
mkdir -p "$ROFI_THEME_DIR"
if [[ ! -f "$ROFI_THEME_DIR/catppuccin-mocha.rasi" ]]; then
    log "Fetching Catppuccin Rofi theme."
    ROFI_TMP="$(mktemp -d)"
    git clone --depth=1 https://github.com/catppuccin/rofi.git "$ROFI_TMP"
    ROFI_MOCHA="$(find "$ROFI_TMP" -type f -iname "*mocha*.rasi" -print -quit)"
    if [[ -n "$ROFI_MOCHA" ]]; then
        cp "$ROFI_MOCHA" "$ROFI_THEME_DIR/catppuccin-mocha.rasi"
    fi
    rm -rf "$ROFI_TMP"
    if [[ ! -f "$ROFI_THEME_DIR/catppuccin-mocha.rasi" ]]; then
        log "WARNING: could not locate the Mocha .rasi in the cloned repo — rofi will use its default theme instead. Check https://github.com/catppuccin/rofi manually."
    fi
else
    log "Rofi Catppuccin theme already present, skipping."
fi

# ---------------------------------------------------------------------------
# 3. i3 config
# ---------------------------------------------------------------------------
log "Writing i3 config."
mkdir -p "$HOME/.config/i3"
backup_if_exists "$HOME/.config/i3/config"

cat > "$HOME/.config/i3/config" << 'EOF'
# i3 config — Catppuccin Mocha theme
# mod4 = Super key

set $mod Mod4

font pango:JetBrains Mono 10

# --- Programs ---
set $term alacritty
set $launcher rofi -show drun -theme ~/.config/rofi/catppuccin-mocha.rasi
set $lock i3lock -c 1e1e2e

# --- Appearance ---
default_border pixel 2
default_floating_border pixel 2
# i3 4.24 uses hide_edge_borders; the old smart_borders syntax is obsolete.
hide_edge_borders smart
gaps inner 10
gaps outer 2
smart_gaps on

# Catppuccin Mocha window border colors
#                       border    backgr.   text      indicator split
client.focused          #89b4fa   #1e1e2e   #cdd6f4   #cba6f7   #89b4fa
client.focused_inactive #313244   #1e1e2e   #a6adc8   #313244   #313244
client.unfocused        #313244   #1e1e2e   #a6adc8   #313244   #313244
client.urgent           #f38ba8   #1e1e2e   #f38ba8   #f38ba8   #f38ba8

# --- Basic bindings ---
bindsym $mod+Return exec $term
# xterm: CPU-only fallback terminal, no GPU rendering dependency — useful
# if Alacritty ever lags (e.g. no OpenGL acceleration in a VM).
bindsym $mod+Shift+Return exec xterm
bindsym $mod+d exec $launcher
bindsym $mod+Shift+c kill
bindsym $mod+Shift+r restart
bindsym $mod+Ctrl+r reload
bindsym $mod+Shift+e exec "i3-nagbar -t warning -m 'Exit i3? This ends your session.' -B 'Yes, exit' 'i3-msg exit'"
bindsym $mod+9 exec $lock

# Screenshots (flameshot)
bindsym Print exec flameshot gui

# --- Focus / move (vim-style + arrows) ---
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

# --- Layout ---
bindsym $mod+z split h
bindsym $mod+v split v
bindsym $mod+f fullscreen toggle
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+e layout toggle split
bindsym $mod+Shift+space floating toggle
bindsym $mod+space focus mode_toggle
bindsym $mod+a focus parent

# --- Workspaces ---
bindsym $mod+1 workspace 1
bindsym $mod+2 workspace 2
bindsym $mod+3 workspace 3
bindsym $mod+4 workspace 4
bindsym $mod+5 workspace 5
bindsym $mod+6 workspace 6
bindsym $mod+7 workspace 7
bindsym $mod+8 workspace 8

bindsym $mod+Shift+1 move container to workspace 1
bindsym $mod+Shift+2 move container to workspace 2
bindsym $mod+Shift+3 move container to workspace 3
bindsym $mod+Shift+4 move container to workspace 4
bindsym $mod+Shift+5 move container to workspace 5
bindsym $mod+Shift+6 move container to workspace 6
bindsym $mod+Shift+7 move container to workspace 7
bindsym $mod+Shift+8 move container to workspace 8

# --- Resize mode ---
bindsym $mod+r mode "resize"
mode "resize" {
    bindsym h resize shrink width 10 px or 10 ppt
    bindsym j resize grow height 10 px or 10 ppt
    bindsym k resize shrink height 10 px or 10 ppt
    bindsym l resize grow width 10 px or 10 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
}

# --- Autostart ---
# Start picom only if it is available; -b keeps i3 startup independent of it.
exec --no-startup-id sh -c 'command -v picom >/dev/null && picom --config "$HOME/.config/picom/picom.conf" --daemon'

# Wallpaper is optional. This avoids a startup error on a fresh install.
exec --no-startup-id sh -c 'if command -v feh >/dev/null && [ -f "$HOME/.config/i3/wallpaper.jpg" ]; then feh --bg-fill "$HOME/.config/i3/wallpaper.jpg"; fi'

exec --no-startup-id dunst
exec --no-startup-id numlockx on
exec_always --no-startup-id "$HOME/.config/polybar/launch.sh"

# Polkit agent — path varies by Debian package layout.
exec --no-startup-id sh -c 'for p in /usr/libexec/polkit-mate-authentication-agent-1 /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 /usr/lib/*/mate-polkit/polkit-mate-authentication-agent-1; do [ -x "$p" ] && exec "$p"; done; exit 0'

# Start nm-applet only when it is actually installed.
exec --no-startup-id sh -c 'command -v nm-applet >/dev/null && nm-applet || true' 
EOF

# ---------------------------------------------------------------------------
# 4. Picom config (Catppuccin-adjacent: soft shadows/rounded corners feel)
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/picom"
backup_if_exists "$HOME/.config/picom/picom.conf"
cat > "$HOME/.config/picom/picom.conf" << 'EOF'
backend = "xrender";
vsync = false;

shadow = true;
shadow-radius = 12;
shadow-opacity = 0.5;
shadow-color = "#11111b";

corner-radius = 8;
rounded-corners-exclude = [
    "window_type = 'dock'",
    "window_type = 'desktop'"
];

fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;

inactive-opacity = 0.95;
active-opacity = 1.0;
EOF

# ---------------------------------------------------------------------------
# 5. Polybar config + launch script
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/polybar"
backup_if_exists "$HOME/.config/polybar/config.ini"

BATTERY_NAME=""
ADAPTER_NAME=""

# Detect the common Linux power-supply names instead of assuming BAT0/AC.
for p in /sys/class/power_supply/BAT*; do
    if [[ -d "$p" ]]; then
        BATTERY_NAME="$(basename "$p")"
        break
    fi
done

for p in /sys/class/power_supply/AC* /sys/class/power_supply/ADP*; do
    if [[ -d "$p" ]]; then
        ADAPTER_NAME="$(basename "$p")"
        break
    fi
done

if [[ -n "$BATTERY_NAME" && -n "$ADAPTER_NAME" ]]; then
    POLYBAR_RIGHT="pulseaudio battery"
else
    POLYBAR_RIGHT="pulseaudio"
    log "No complete battery/AC pair detected; omitting Polybar battery module."
fi

cat > "$HOME/.config/polybar/config.ini" << EOF
; Catppuccin Mocha palette
[colors]
base     = #1e1e2e
mantle   = #181825
text     = #cdd6f4
subtext0 = #a6adc8
surface0 = #313244
blue     = #89b4fa
mauve    = #cba6f7
green    = #a6e3a1
red      = #f38ba8
yellow   = #f9e2af
peach    = #fab387

[bar/main]
width = 100%
height = 28
background = \${colors.base}
foreground = \${colors.text}
font-0 = JetBrains Mono:size=10;2

modules-left = i3
modules-center = date
modules-right = ${POLYBAR_RIGHT}

[ module/i3 ]
type = internal/i3
format = <label-state> <label-mode>
label-focused = %index%
label-focused-background = \${colors.surface0}
label-focused-foreground = \${colors.blue}
label-focused-padding = 2
label-unfocused = %index%
label-unfocused-foreground = \${colors.subtext0}
label-unfocused-padding = 2

[module/date]
type = internal/date
interval = 1
date = %H:%M
date-alt = %Y-%m-%d %H:%M:%S
label = %date%
label-foreground = \${colors.mauve}

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <label-volume>
label-volume = VOL %percentage%%
label-volume-foreground = \${colors.green}
label-muted = VOL muted
label-muted-foreground = \${colors.red}
EOF

# Polybar's section name must not contain the accidental spaces introduced
# above; normalize it after generation.
sed -i 's/^\[ module\/i3 \]$/[module\/i3]/' "$HOME/.config/polybar/config.ini"

if [[ -n "$BATTERY_NAME" && -n "$ADAPTER_NAME" ]]; then
    cat >> "$HOME/.config/polybar/config.ini" << EOF

[module/battery]
type = internal/battery
battery = ${BATTERY_NAME}
adapter = ${ADAPTER_NAME}
format-charging = <label-charging>
format-discharging = <label-discharging>
label-charging = BAT %percentage%% (charging)
label-discharging = BAT %percentage%%
label-foreground = \${colors.peach}
EOF
fi

backup_if_exists "$HOME/.config/polybar/launch.sh"
cat > "$HOME/.config/polybar/launch.sh" << 'EOF'
#!/bin/sh
killall -q polybar 2>/dev/null || true
while pgrep -u "$UID" -x polybar >/dev/null; do sleep 1; done
polybar main >/dev/null 2>&1 &
EOF

chmod +x "$HOME/.config/polybar/launch.sh"

# ---------------------------------------------------------------------------
# 6. Register i3 as a selectable LightDM session
# ---------------------------------------------------------------------------
# Validate the generated i3 configuration before registering it.
if ! i3 -C -c "$HOME/.config/i3/config"; then
    log "ERROR: generated i3 configuration failed validation."
    exit 1
fi
log "i3 configuration validated successfully."

I3_SESSION_FILE="/usr/share/xsessions/i3-catppuccin.desktop"
log "Registering i3 session for LightDM."
sudo tee "$I3_SESSION_FILE" > /dev/null << 'EOF'
[Desktop Entry]
Name=i3 (Catppuccin)
Comment=Tiling window manager, Catppuccin Mocha theme
Exec=i3
TryExec=i3
Type=Application
DesktopNames=i3
EOF

# Keep LightDM as the login manager when it is already installed by the main
# XFCE setup. Do not force a display-manager reconfiguration here.
if command -v lightdm >/dev/null 2>&1; then
    sudo systemctl enable lightdm >/dev/null 2>&1 || true
fi

log "Done. Log out and choose 'i3 (Catppuccin)' from LightDM's session menu."
log "XFCE has not been modified. Wallpaper is optional: place wallpaper.jpg at ~/.config/i3/wallpaper.jpg when desired."
log "If NetworkManager/nm-applet is not installed, networking remains untouched and i3 simply starts without a tray network icon."
