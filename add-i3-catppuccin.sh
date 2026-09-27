#!/usr/bin/env bash
#
# add-i3-catppuccin.sh
# Adds i3 (tiling window manager) as an ADDITIONAL LightDM session,
# themed in Catppuccin Mocha, alongside your existing XFCE setup.
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
apt_install i3 polybar picom feh i3lock dunst mate-polkit numlockx \
    fonts-font-awesome git
# Defensive — already installed by the main script in the normal flow, but
# harmless (and correct) to ensure here too if this script runs standalone.
apt_install rofi alacritty flameshot

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
    find "$ROFI_TMP" -iname "*mocha*.rasi" -exec cp {} "$ROFI_THEME_DIR/catppuccin-mocha.rasi" \; 2>/dev/null || true
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

font pango:JetBrainsMono Nerd Font 10

# --- Programs ---
set $term alacritty
set $launcher rofi -show drun -theme ~/.config/rofi/catppuccin-mocha.rasi
set $lock i3lock -c 1e1e2e

# --- Appearance ---
default_border pixel 2
default_floating_border pixel 2
hide_edge_borders smart
gaps inner 10
gaps outer 2
smart_gaps on
smart_borders on

# Catppuccin Mocha window border colors
#                       border    backgr.   text      indicator split
client.focused          #89b4fa   #1e1e2e   #cdd6f4   #cba6f7   #89b4fa
client.focused_inactive #313244   #1e1e2e   #a6adc8   #313244   #313244
client.unfocused        #313244   #1e1e2e   #a6adc8   #313244   #313244
client.urgent           #f38ba8   #1e1e2e   #f38ba8   #f38ba8   #f38ba8

# --- Basic bindings ---
bindsym $mod+Return exec $term
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
exec --no-startup-id picom --config ~/.config/picom/picom.conf
exec --no-startup-id feh --bg-fill ~/.config/i3/wallpaper.jpg
exec --no-startup-id dunst
exec --no-startup-id numlockx on
exec_always --no-startup-id $HOME/.config/polybar/launch.sh

# Polkit agent — path varies by system, try common locations
exec --no-startup-id sh -c 'for p in /usr/libexec/polkit-mate-authentication-agent-1 /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 /usr/lib/*/mate-polkit/polkit-mate-authentication-agent-1; do [ -x "$p" ] && exec "$p"; done'

# Network tray icon, if you've enabled NetworkManager in the main script
exec --no-startup-id nm-applet
EOF

# ---------------------------------------------------------------------------
# 4. Picom config (Catppuccin-adjacent: soft shadows/rounded corners feel)
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/picom"
backup_if_exists "$HOME/.config/picom/picom.conf"
cat > "$HOME/.config/picom/picom.conf" << 'EOF'
backend = "glx";
vsync = true;

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
cat > "$HOME/.config/polybar/config.ini" << 'EOF'
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
background = ${colors.base}
foreground = ${colors.text}
font-0 = JetBrainsMono Nerd Font:size=10;2
font-1 = Font Awesome 6 Free:style=Solid:size=10;2

modules-left = i3
modules-center = date
modules-right = pulseaudio battery

[module/i3]
type = internal/i3
format = <label-state> <label-mode>
label-focused = %index%
label-focused-background = ${colors.surface0}
label-focused-foreground = ${colors.blue}
label-focused-padding = 2
label-unfocused = %index%
label-unfocused-foreground = ${colors.subtext0}
label-unfocused-padding = 2

[module/date]
type = internal/date
interval = 1
date = %H:%M
date-alt = %Y-%m-%d %H:%M:%S
label = %date%
label-foreground = ${colors.mauve}

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <ramp-volume> <label-volume>
label-volume-foreground = ${colors.green}
label-muted = muted
label-muted-foreground = ${colors.red}
ramp-volume-0 = 
ramp-volume-1 = 
ramp-volume-2 = 

[module/battery]
type = internal/battery
; Adjust these two to match your hardware — check with:
;   ls /sys/class/power_supply/
battery = BAT0
adapter = AC
format-charging = <animation-charging> <label-charging>
format-discharging = <ramp-capacity> <label-discharging>
label-charging = %percentage%%
label-discharging = %percentage%%
label-foreground = ${colors.peach}
ramp-capacity-0 = 
ramp-capacity-1 = 
ramp-capacity-2 = 
ramp-capacity-3 = 
ramp-capacity-4 = 
animation-charging-0 = 
animation-charging-1 = 
animation-charging-2 = 
animation-charging-framerate = 750
EOF

backup_if_exists "$HOME/.config/polybar/launch.sh"
cat > "$HOME/.config/polybar/launch.sh" << 'EOF'
#!/bin/sh
killall -q polybar
while pgrep -u "$UID" -x polybar >/dev/null; do sleep 1; done
polybar main &
EOF
chmod +x "$HOME/.config/polybar/launch.sh"

# ---------------------------------------------------------------------------
# 6. Register i3 as a selectable LightDM session
# ---------------------------------------------------------------------------
DWM_LIKE_DESKTOP_FILE="/usr/share/xsessions/i3-catppuccin.desktop"
if [[ ! -f "$DWM_LIKE_DESKTOP_FILE" ]]; then
    log "Registering i3 session for LightDM."
    sudo tee "$DWM_LIKE_DESKTOP_FILE" > /dev/null << 'EOF'
[Desktop Entry]
Name=i3 (Catppuccin)
Comment=Tiling window manager, Catppuccin Mocha theme
Exec=i3
Type=Application
EOF
fi

log "Done. Log out and pick 'i3 (Catppuccin)' from the session menu at the LightDM login screen. Your XFCE session is untouched."
log "Two things worth checking after first login: (1) the polybar battery module's 'battery'/'adapter' names — verify with 'ls /sys/class/power_supply/' and edit ~/.config/polybar/config.ini if they don't match; (2) you'll want a wallpaper at ~/.config/i3/wallpaper.jpg, or edit the feh line in ~/.config/i3/config to point elsewhere."
