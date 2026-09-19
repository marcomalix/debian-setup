#!/usr/bin/env bash
#
# debian-postinstall.sh
# Post-install setup for a fresh Debian 13 (trixie) netinstall — daily-use
# workstation for scientific writing, browsing, R/RStudio and LibreOffice
# Calc work.
#
# Usage:
#   chmod +x debian-postinstall.sh
#   ./debian-postinstall.sh
#
# Do NOT run this as root / with sudo. It calls sudo itself where needed.
# Run it as your normal user.

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. CONFIG — flip sections on/off here before running.
# ---------------------------------------------------------------------------
DO_SYSTEM_UPGRADE=true
DO_DESKTOP_ENV=true          # xfce4 + goodies
DO_CORE_APPS=true            # alacritty, geany, etc.
DO_THEMING=true               # arc-theme, bibata cursors, papirus icons, celestial gtk theme
DO_FONTS=true                  # Inter, JetBrains Mono, Google Sans Code
DO_CREATIVE_GIS=true          # gimp, inkscape, qgis
DO_BACKPORTS_LIBREOFFICE=true
DO_ZOTERO=true
DO_FIREFOX=true
DO_BRAVE=true                  # installs Brave Origin (stripped-down, no ads/Leo/Rewards/telemetry)
DO_BRAVE_BROWSER=false         # OFF by default — regular full-feature Brave, installed alongside Origin if true
DO_BACKUP_TOOLS=true          # timeshift + borgbackup + vorta (GUI for borg)
DO_R_RSTUDIO=true             # r-base + RStudio Desktop
DO_LAPTOP_POWER=true           # zram, TLP, CPU microcode, SSD trim — see section 13
DO_SECURITY=true               # UFW firewall + Bluetooth — see section 14
DO_EXTRAS=true                  # xournalpp, pdfarranger, keepassxc, synaptic, redshift — see section 15
DO_FLATPAK=false               # OFF by default — adds Flathub as an extra app source, see section 15
DO_NETWORK_MANAGER=true       # see section 16 for what to check if the tray icon shows nothing
DO_AUDIO=true                  # pipewire-audio + pavucontrol — see section 17
DO_PRINT_SCAN=true             # cups, cups-pdf, gutenprint, simple-scan — see section 18
DO_DISK_HEALTH=true            # smartmontools, baobab, gparted — see section 19
DO_GVFS_EXTRAS=true            # mount cameras/phones/network shares in Thunar — see section 20
DO_ARCHIVE_TOOLS=true          # p7zip, unrar, Thunar archive plugin — see section 21
DO_DESKTOP_EXTRAS=true         # flameshot, font-manager, catfish, meld — see section 22
DO_CLI_TOOLS=true              # bat, eza, fd-find, ripgrep, tldr, tmux, ncdu — see section 23
DO_HW_MONITORING=true          # lm-sensors, inxi — see section 24
DO_RESEARCH_EXTRAS=false      # OFF by default — LaTeX + pandoc, see section 25
DO_THUNDERBIRD=false          # OFF by default — flip to true whenever you want it
DO_RESTORE_DOTFILES=true      # restore your XFCE panel + Geany config, see section 27
DO_CLEANUP=true

# RStudio isn't in the Debian repos, so it's installed from a direct .deb.
# This URL WILL go stale — Posit ships a new version every few months.
# Before running, check the current one at https://posit.co/download/rstudio-desktop/
# (look for the "Ubuntu / Debian" row) and update this if it's changed.
RSTUDIO_DEB_URL="https://download1.rstudio.org/electron/jammy/amd64/rstudio-2026.08.2-200-amd64.deb"

# Celestial GTK theme isn't packaged for Debian either — it's built and
# installed from source via its own install.sh (this is the standard,
# widely-used pattern for GTK themes; no sudo needed, it installs to
# ~/.themes for your user only).
CELESTIAL_THEME_REPO="https://github.com/zquestz/celestial-gtk-theme.git"

# Directory holding your exported XFCE panel + Geany config, expected to sit
# right next to this script (see section 14 for how to create it).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${SCRIPT_DIR}/dotfiles"

LOG_FILE="$HOME/debian-postinstall.log"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

fail_trap() {
    local exit_code=$?
    local line_no=$1
    log "ERROR: script failed at line ${line_no} (exit code ${exit_code}). See ${LOG_FILE} for details."
    exit "${exit_code}"
}
trap 'fail_trap $LINENO' ERR

require_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        echo "Don't run this script as root/sudo. Run it as your normal user; it will call sudo itself." >&2
        exit 1
    fi
}

apt_install() {
    # Installs only packages that aren't already installed.
    local pkgs=("$@")
    local to_install=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            to_install+=("$pkg")
        fi
    done
    if [[ ${#to_install[@]} -gt 0 ]]; then
        log "Installing: ${to_install[*]}"
        sudo apt-get install -y "${to_install[@]}"
    else
        log "Already installed, skipping: ${pkgs[*]}"
    fi
}

restore_config_dir() {
    # Copies a saved config directory into place, backing up whatever is
    # already there instead of silently overwriting it.
    local src="$1" dest="$2"
    if [[ ! -d "$src" ]]; then
        log "No saved config at ${src}, skipping."
        return
    fi
    if [[ -d "$dest" ]]; then
        local backup="${dest}.bak.$(date '+%Y%m%d%H%M%S')"
        log "Backing up existing ${dest} to ${backup}"
        mv "$dest" "$backup"
    fi
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
    log "Restored ${dest}"
}

latest_github_zip_url() {
    # Prints the .zip asset URL from a GitHub repo's latest release.
    # Used for fonts that aren't packaged for Debian (no version to pin —
    # always grabs whatever is current).
    local repo="$1"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
        | grep -oP '"browser_download_url":\s*"\K[^"]+\.zip' \
        | head -n1
}

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
require_not_root
: > "$LOG_FILE"  # truncate/create log file
log "Starting Debian post-install script."

# Cache sudo credentials once up front, then keep them alive in the
# background so you're not prompted again mid-script.
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null & )

# ---------------------------------------------------------------------------
# 1. System update
# ---------------------------------------------------------------------------
if [[ "$DO_SYSTEM_UPGRADE" == true ]]; then
    log "Updating package index and upgrading base system."
    sudo apt-get update
    sudo apt-get upgrade -y
fi

# ---------------------------------------------------------------------------
# 2. Desktop environment + display manager
# ---------------------------------------------------------------------------
# xfce4/xfce4-goodies give you the desktop itself, but NOT a display manager
# (the graphical login screen that starts your session and lets you pick
# XFCE at boot). A netinstall with no desktop task selected boots straight
# to a text login otherwise — that's the "no graphical connection" you saw.
if [[ "$DO_DESKTOP_ENV" == true ]]; then
    log "Installing XFCE desktop environment."
    apt_install xfce4 xfce4-goodies

    log "Installing and enabling LightDM display manager."
    apt_install lightdm lightdm-gtk-greeter

    sudo systemctl enable lightdm
    # Make sure the system actually boots to a graphical login rather than
    # a text console (relevant if the netinstall had no desktop task
    # selected, so it's still set to boot to text mode).
    sudo systemctl set-default graphical.target

    log "LightDM enabled. A reboot (or 'sudo systemctl start lightdm' on a machine with no session yet) is needed to reach the graphical login."
fi

# ---------------------------------------------------------------------------
# 3. Core applications (official Debian repos)
# ---------------------------------------------------------------------------
if [[ "$DO_CORE_APPS" == true ]]; then
    log "Installing core applications."

    apt_install alacritty evince rofi plank qalculate-gtk
    apt_install htop btop fastfetch
    apt_install geany geany-plugin-addons geany-plugin-git-changebar \
        geany-plugin-overview geany-plugin-spellcheck geany-plugin-treebrowser \
        geany-plugin-markdown
fi

# ---------------------------------------------------------------------------
# 4. Theming: Arc + Bibata (as you had), plus Papirus icons + Celestial GTK theme
# ---------------------------------------------------------------------------
if [[ "$DO_THEMING" == true ]]; then
    log "Installing theming packages."
    apt_install arc-theme bibata-cursor-theme papirus-icon-theme orchis-gtk-theme

    # Celestial theme: built from source, installs to ~/.themes (no sudo).
    if [[ ! -d "$HOME/.themes/Celestial" && ! -d "$HOME/.themes/Celestial-dark" ]]; then
        log "Installing Celestial GTK theme."
        apt_install sassc git
        CELESTIAL_TMP="$(mktemp -d)"
        git clone --depth=1 "$CELESTIAL_THEME_REPO" "$CELESTIAL_TMP"
        (cd "$CELESTIAL_TMP" && ./install.sh)
        rm -rf "$CELESTIAL_TMP"
    else
        log "Celestial theme already installed, skipping."
    fi

    # Surfn icons: also not packaged, built by Erik Dubois, distributed as a
    # plain folder in the repo rather than a build/install script — just
    # copied straight into ~/.icons.
    if [[ ! -d "$HOME/.icons/Surfn" ]]; then
        log "Installing Surfn icon theme."
        apt_install git
        SURFN_TMP="$(mktemp -d)"
        git clone --depth=1 https://github.com/erikdubois/Surfn.git "$SURFN_TMP"
        mkdir -p "$HOME/.icons"
        # The repo's internal folder layout isn't fixed/documented, so
        # locate the actual theme folder(s) by finding index.theme files
        # (the standard marker of a valid icon theme directory) rather than
        # assuming a fixed subfolder name.
        mapfile -t SURFN_THEME_DIRS < <(find "$SURFN_TMP" -mindepth 1 -maxdepth 4 -name "index.theme" -exec dirname {} \;)
        if [[ ${#SURFN_THEME_DIRS[@]} -gt 0 ]]; then
            for d in "${SURFN_THEME_DIRS[@]}"; do
                cp -r "$d" "$HOME/.icons/"
            done
        else
            log "WARNING: could not locate a Surfn theme folder in the cloned repo — skipping. Check https://github.com/erikdubois/Surfn manually."
        fi
        rm -rf "$SURFN_TMP"
    else
        log "Surfn icons already installed, skipping."
    fi

    # Colloid: also unpackaged, built via its own install.sh (same pattern
    # as Celestial). Using the catppuccin color scheme with all folder
    # colors for the soft/pastel look, and installing every folder color so
    # you can pick your favorite afterward in the icon theme selector.
    if ! find "$HOME/.local/share/icons" -maxdepth 1 -iname 'Colloid*' 2>/dev/null | grep -q .; then
        log "Building and installing Colloid icon theme (catppuccin/pastel scheme)."
        apt_install git
        COLLOID_TMP="$(mktemp -d)"
        git clone --depth=1 https://github.com/vinceliuice/Colloid-icon-theme.git "$COLLOID_TMP"
        (cd "$COLLOID_TMP" && ./install.sh -s catppuccin -t all)
        rm -rf "$COLLOID_TMP"
    else
        log "Colloid icons already installed, skipping."
    fi

    # Tela Circle: same author/pattern as Colloid, also unpackaged.
    # -a installs every color variant at once, pick your favorite afterward.
    if ! find "$HOME/.local/share/icons" -maxdepth 1 -iname 'Tela-circle*' 2>/dev/null | grep -q .; then
        log "Building and installing Tela Circle icon theme."
        apt_install git
        TELA_TMP="$(mktemp -d)"
        git clone --depth=1 https://github.com/vinceliuice/Tela-circle-icon-theme.git "$TELA_TMP"
        (cd "$TELA_TMP" && ./install.sh -a)
        rm -rf "$TELA_TMP"
    else
        log "Tela Circle icons already installed, skipping."
    fi

    log "Theme + icons installed. Set them in Settings > Appearance (GTK theme: Celestial or Orchis; icons: Papirus, Surfn, Colloid, or Tela Circle) and Settings > Window Manager (matching xfwm4 theme) after login."
fi

# ---------------------------------------------------------------------------
# 5. Fonts: Inter, JetBrains Mono, Google Sans Code
# ---------------------------------------------------------------------------
if [[ "$DO_FONTS" == true ]]; then
    log "Installing fonts."
    # Inter and JetBrains Mono are packaged for Debian.
    apt_install fonts-inter fonts-jetbrains-mono

    # Google Sans Code is not packaged anywhere — it only ships as GitHub
    # release zips. Fetched dynamically (see latest_github_zip_url) rather
    # than a pinned URL, since there's no Debian package to track a version
    # for anyway.
    GSC_DIR="$HOME/.local/share/fonts/GoogleSansCode"
    if [[ ! -d "$GSC_DIR" ]]; then
        log "Installing Google Sans Code."
        apt_install unzip
        GSC_URL="$(latest_github_zip_url "googlefonts/googlesans-code")"
        if [[ -n "$GSC_URL" ]]; then
            GSC_ZIP="$(mktemp --suffix=.zip)"
            if wget -q -O "$GSC_ZIP" "$GSC_URL"; then
                mkdir -p "$GSC_DIR"
                unzip -q -o "$GSC_ZIP" -d "$GSC_DIR"
                fc-cache -f "$GSC_DIR" > /dev/null
            else
                log "WARNING: failed to download Google Sans Code (network issue) — skipping. Rerun the script later to retry just this bit."
            fi
            rm -f "$GSC_ZIP"
        else
            log "WARNING: could not find a Google Sans Code release download — skipping. Check https://github.com/googlefonts/googlesans-code/releases/latest manually."
        fi
    else
        log "Google Sans Code already installed, skipping."
    fi
fi

# ---------------------------------------------------------------------------
# 6. Creative & GIS tools
# ---------------------------------------------------------------------------
if [[ "$DO_CREATIVE_GIS" == true ]]; then
    log "Installing GIMP, Inkscape, and QGIS."
    apt_install gimp inkscape qgis
fi

# ---------------------------------------------------------------------------
# 7. LibreOffice from backports
# ---------------------------------------------------------------------------
if [[ "$DO_BACKPORTS_LIBREOFFICE" == true ]]; then
    log "Configuring trixie-backports and installing LibreOffice."
    BACKPORTS_FILE="/etc/apt/sources.list.d/debian-backports.sources"
    if [[ ! -f "$BACKPORTS_FILE" ]]; then
        sudo tee "$BACKPORTS_FILE" > /dev/null << 'EOF'
Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main
Enabled: yes
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    else
        log "Backports source already configured, skipping."
    fi
    sudo apt-get update
    if ! dpkg -s libreoffice &>/dev/null; then
        # libreoffice-gtk3 must come from backports too, alongside the main
        # package — if it's left to install from stable while LibreOffice
        # itself is from backports, you get a version mismatch: LibreOffice
        # falls back to an older/inconsistent GTK3 integration, which shows
        # up as outdated-looking icons/widgets and dialog theming that
        # doesn't match the rest of your desktop.
        sudo apt-get install -y -t trixie-backports libreoffice libreoffice-gtk3
    else
        log "LibreOffice already installed, skipping."
    fi
fi

# ---------------------------------------------------------------------------
# 8. Zotero
# ---------------------------------------------------------------------------
if [[ "$DO_ZOTERO" == true ]]; then
    if ! dpkg -s zotero &>/dev/null; then
        log "Installing Zotero."
        # Third-party install script — review it before trusting it blindly:
        # https://github.com/retorquere/zotero-pkg
        wget -qO- https://raw.githubusercontent.com/retorquere/zotero-pkg/master/install.sh | sudo bash
        sudo apt-get update
        sudo apt-get install -y zotero
    else
        log "Zotero already installed, skipping."
    fi
fi

# ---------------------------------------------------------------------------
# 9. Firefox (Mozilla's own repo, for the current release rather than Debian's)
# ---------------------------------------------------------------------------
if [[ "$DO_FIREFOX" == true ]]; then
    log "Configuring Mozilla repo and installing Firefox."
    sudo install -d -m 0755 /etc/apt/keyrings

    KEYRING="/etc/apt/keyrings/packages.mozilla.org.asc"
    if [[ ! -f "$KEYRING" ]]; then
        wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | \
            sudo tee "$KEYRING" > /dev/null
    fi

    SOURCES_FILE="/etc/apt/sources.list.d/mozilla.sources"
    if [[ ! -f "$SOURCES_FILE" ]]; then
        sudo tee "$SOURCES_FILE" > /dev/null << EOF
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: ${KEYRING}
EOF
    fi

    PIN_FILE="/etc/apt/preferences.d/mozilla"
    if [[ ! -f "$PIN_FILE" ]]; then
        sudo tee "$PIN_FILE" > /dev/null << 'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF
    fi

    sudo apt-get update
    apt_install firefox
fi

# ---------------------------------------------------------------------------
# 10. Brave (Origin by default; regular Brave Browser is opt-in)
# ---------------------------------------------------------------------------
# Brave Origin is a stripped-down Brave build — Leo AI, Rewards, Ads, Talk,
# VPN, Wallet, daily usage pings, and analytics (P3A) are compiled out
# entirely rather than just hidden. Free on Linux. It's not a separate
# install method — it's just a different package name in Brave's own apt
# repo, the same repo regular Brave uses — so this sets up that repo
# properly (key + sources file, same transparent pattern as the Firefox
# section above) instead of piping their install script into sh.
if [[ "$DO_BRAVE" == true ]]; then
    log "Configuring Brave's apt repo."
    sudo install -d -m 0755 /usr/share/keyrings

    BRAVE_KEYRING="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
    if [[ ! -f "$BRAVE_KEYRING" ]]; then
        sudo curl -fsSLo "$BRAVE_KEYRING" https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    fi

    BRAVE_SOURCES="/etc/apt/sources.list.d/brave-browser-release.sources"
    if [[ ! -f "$BRAVE_SOURCES" ]]; then
        sudo curl -fsSLo "$BRAVE_SOURCES" https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
    fi

    sudo apt-get update
    apt_install brave-origin

    if [[ "$DO_BRAVE_BROWSER" == true ]]; then
        log "Installing regular Brave Browser (full feature set) alongside Origin."
        apt_install brave-browser
    fi
fi

# ---------------------------------------------------------------------------
# 11. Backups: Timeshift (system snapshots) + Borg (file/data backups)
# ---------------------------------------------------------------------------
if [[ "$DO_BACKUP_TOOLS" == true ]]; then
    log "Installing Timeshift and Borg backup tools."
    # Timeshift: snapshots your SYSTEM (like a Windows System Restore point).
    # Good for undoing a bad upgrade or config change. It is NOT meant for
    # backing up your personal documents/thesis — exclude /home by default
    # in its settings, and use Borg (below) for that instead.
    apt_install timeshift

    # Borg: deduplicated, encrypted backups — ideal for your documents,
    # articles, thesis, RStudio projects, etc. It's normally used from the
    # command line; Vorta gives it a proper GUI (system tray icon, scheduled
    # backups, one-click restore) so you don't have to memorise borg commands.
    apt_install borgbackup vorta
fi

# ---------------------------------------------------------------------------
# 12. R and RStudio Desktop
# ---------------------------------------------------------------------------
if [[ "$DO_R_RSTUDIO" == true ]]; then
    log "Installing R."
    apt_install r-base r-base-dev

    if ! dpkg -s rstudio &>/dev/null; then
        log "Installing RStudio Desktop from ${RSTUDIO_DEB_URL}"
        RSTUDIO_DEB="/tmp/$(basename "$RSTUDIO_DEB_URL")"
        wget -q -O "$RSTUDIO_DEB" "$RSTUDIO_DEB_URL"
        # apt-get install (not dpkg -i) so any missing dependencies of the
        # .deb get pulled in automatically.
        sudo apt-get install -y "$RSTUDIO_DEB"
        rm -f "$RSTUDIO_DEB"
    else
        log "RStudio already installed, skipping."
    fi
fi

# ---------------------------------------------------------------------------
# 13. Laptop power & battery: zram, TLP, CPU microcode, SSD trim
# ---------------------------------------------------------------------------
if [[ "$DO_LAPTOP_POWER" == true ]]; then
    log "Setting up zram swap."
    apt_install zram-tools
    sudo systemctl enable --now zramswap.service 2>/dev/null || true

    log "Installing TLP for laptop power/battery management."
    apt_install tlp tlp-rdw powertop
    # TLP and power-profiles-daemon manage the same thing and conflict —
    # power-profiles-daemon is sometimes pulled in by GNOME-adjacent
    # packages even on XFCE, so make sure it's off if present.
    if dpkg -s power-profiles-daemon &>/dev/null; then
        log "Disabling power-profiles-daemon (conflicts with TLP)."
        sudo systemctl disable --now power-profiles-daemon
    fi
    sudo systemctl enable tlp

    log "Installing CPU microcode updates."
    CPU_VENDOR="$(grep -m1 vendor_id /proc/cpuinfo | awk '{print $3}')"
    if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
        apt_install intel-microcode
    elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
        apt_install amd64-microcode
    else
        log "Could not detect CPU vendor for a microcode package, skipping."
    fi

    log "Installing Linux kernel headers."
    # Needed to build any DKMS kernel module — VirtualBox Guest Additions,
    # some wifi/printer drivers, etc. Tracks whatever kernel is currently
    # running rather than a fixed version.
    apt_install linux-headers-amd64

    log "Enabling weekly SSD trim."
    sudo systemctl enable fstrim.timer
fi

# ---------------------------------------------------------------------------
# 14. Security: firewall + Bluetooth
# ---------------------------------------------------------------------------
if [[ "$DO_SECURITY" == true ]]; then
    log "Installing and enabling UFW firewall (deny incoming, allow outgoing)."
    apt_install ufw
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw --force enable

    log "Installing Bluetooth support."
    apt_install bluez blueman
fi

# ---------------------------------------------------------------------------
# 15. Handy extras
# ---------------------------------------------------------------------------
if [[ "$DO_EXTRAS" == true ]]; then
    log "Installing convenience apps."
    # xournalpp: annotate PDFs (papers, scanned documents) with a stylus/mouse.
    # pdfarranger: merge/reorder/split PDF pages — handy for assembling a
    #   thesis from separate chapter files or scanned material.
    # keepassxc: local password manager.
    # synaptic: GUI package manager — browse/install/remove Debian packages
    #   without needing apt commands, useful day-to-day since you're not
    #   coming from a dev background.
    # gammastep: warms screen color in the evening — easier on the eyes for
    #   long writing sessions. This replaces Redshift, whose upstream project
    #   was archived in April 2026; gammastep is the actively maintained
    #   fork of the same tool (same idea, same config style).
    # vlc: plays basically anything — video, audio, streams.
    apt_install xournalpp pdfarranger keepassxc synaptic gammastep vlc

    if [[ "$DO_FLATPAK" == true ]]; then
        log "Setting up Flatpak + Flathub."
        apt_install flatpak
        sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
fi

# ---------------------------------------------------------------------------
# 16. Networking: NetworkManager applet (OFF by default — read this first)
# ---------------------------------------------------------------------------
# Your netinstall almost certainly set up networking the traditional Debian
# way, via /etc/network/interfaces — NOT NetworkManager. Installing NM on
# top of that USUALLY coexists fine (it won't touch an interface that's
# already explicitly configured there), but it can also just show nothing
# useful in the tray if it doesn't take over the connection — it's not
# "broken", just not guaranteed to give you the wifi-switching UI you'd
# expect. If you enable this and the tray icon shows no networks, check
# /etc/network/interfaces — you likely need to remove or comment out the
# entry for your interface there so NetworkManager can manage it instead.
if [[ "$DO_NETWORK_MANAGER" == true ]]; then
    log "Installing NetworkManager + tray applet."
    apt_install network-manager network-manager-applet
fi

# ---------------------------------------------------------------------------
# 17. Audio: PipeWire + volume control GUI
# ---------------------------------------------------------------------------
if [[ "$DO_AUDIO" == true ]]; then
    log "Installing audio stack."
    # Debian 13 defaults to PipeWire over PulseAudio; pipewire-audio is the
    # standard meta-package for it. pavucontrol gives you a proper mixer/
    # routing GUI. Both are safe no-ops if your desktop task already pulled
    # these in as dependencies.
    apt_install pipewire-audio pavucontrol
fi

# ---------------------------------------------------------------------------
# 18. Printing & scanning
# ---------------------------------------------------------------------------
if [[ "$DO_PRINT_SCAN" == true ]]; then
    log "Installing printing and scanning support."
    apt_install cups printer-driver-cups-pdf printer-driver-gutenprint system-config-printer simple-scan
fi

# ---------------------------------------------------------------------------
# 19. Disk health & management
# ---------------------------------------------------------------------------
if [[ "$DO_DISK_HEALTH" == true ]]; then
    log "Installing disk health and management tools."
    # smartmontools: warns you before a failing drive costs you data —
    # pairs naturally with the Borg/Timeshift backups from section 11.
    apt_install smartmontools baobab gparted
fi

# ---------------------------------------------------------------------------
# 20. Removable media / device mounting in Thunar
# ---------------------------------------------------------------------------
if [[ "$DO_GVFS_EXTRAS" == true ]]; then
    log "Installing extra GVFS backends for Thunar."
    # Lets Thunar mount cameras/phones/network shares directly — relevant
    # if you're importing field photos from coastal work off a camera.
    apt_install gvfs-backends
fi

# ---------------------------------------------------------------------------
# 21. Archive handling
# ---------------------------------------------------------------------------
if [[ "$DO_ARCHIVE_TOOLS" == true ]]; then
    log "Installing archive tools."
    # unrar-free instead of unrar: the full RARLAB unrar lives in Debian's
    # non-free component, not enabled by default, and this script doesn't
    # touch your sources.list to turn that on. unrar-free handles plain
    # RAR5 archives fine on Debian 13; it just can't open password-encrypted
    # RAR files. If you hit that limitation, enable non-free in
    # /etc/apt/sources.list.d/debian.sources yourself and swap to `unrar`.
    apt_install p7zip-full unrar-free thunar-archive-plugin
fi

# ---------------------------------------------------------------------------
# 22. Desktop extras: screenshots, font manager, file search, diff tool
# ---------------------------------------------------------------------------
if [[ "$DO_DESKTOP_EXTRAS" == true ]]; then
    log "Installing desktop convenience apps."
    # flameshot: annotated screenshots (arrows, blur, text) — more useful
    #   than the basic screenshooter when building teaching slides.
    # font-manager: preview/manage the fonts installed in section 5.
    # catfish: quick file search GUI, complements Thunar.
    # meld: side-by-side diff/merge — handy for comparing script/document
    #   versions, including this very script.
    apt_install flameshot font-manager catfish meld
fi

# ---------------------------------------------------------------------------
# 23. CLI quality-of-life tools
# ---------------------------------------------------------------------------
if [[ "$DO_CLI_TOOLS" == true ]]; then
    log "Installing CLI tools."
    apt_install bat eza fd-find ripgrep tealdeer tmux ncdu
    log "tealdeer installed (command is still 'tldr'). Run 'tldr --update' once to download its cheatsheet cache — it doesn't do this automatically on install."

    # Debian ships bat's binary as "batcat" and fd-find's as "fdfind" —
    # both to avoid clashing with unrelated older packages that already
    # used the names "bat" and "fd". Symlinking them makes the commands
    # work under their upstream names, matching how you'd expect to type
    # them from the Arch list.
    mkdir -p "$HOME/.local/bin"
    ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
    ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"
    log "bat/fd symlinked into ~/.local/bin — make sure that's on your PATH (it is by default in most Debian shell setups once the directory exists, but check after reboot)."
fi

# ---------------------------------------------------------------------------
# 24. Hardware monitoring
# ---------------------------------------------------------------------------
if [[ "$DO_HW_MONITORING" == true ]]; then
    log "Installing hardware monitoring tools."
    apt_install lm-sensors inxi
    log "lm-sensors installed. Run 'sudo sensors-detect' once manually (it asks interactive yes/no questions about your hardware, so it's not run automatically here) to enable full sensor detection."
fi

# ---------------------------------------------------------------------------
# 25. Optional: LaTeX + Pandoc (OFF by default)
# ---------------------------------------------------------------------------
# Useful for thesis/article writing, but it's an opinionated choice (LaTeX
# vs. just using LibreOffice Writer) and a real download, so it's off until
# you decide you want it.
#
#   texlive-latex-extra, texlive-fonts-recommended, texlive-lang-french
#       -> LaTeX, if your thesis/journal template needs it rather than
#          LibreOffice Writer. (texlive-full is ~5-7 GB; this subset covers
#          the vast majority of article/thesis templates. Swap/add
#          texlive-lang-arabic too if you need it.)
#   pandoc
#       -> converts between Markdown/LaTeX/Word/PDF; also what RStudio uses
#          under the hood to knit R Markdown/Quarto documents to PDF/Word.
#
if [[ "$DO_RESEARCH_EXTRAS" == true ]]; then
    log "Installing LaTeX and Pandoc."
    apt_install texlive-latex-extra texlive-fonts-recommended texlive-lang-french
    apt_install pandoc
fi

# ---------------------------------------------------------------------------
# 26. Optional: Thunderbird (OFF by default — install whenever you want it)
# ---------------------------------------------------------------------------
if [[ "$DO_THUNDERBIRD" == true ]]; then
    log "Installing Thunderbird."
    apt_install thunderbird
fi

# ---------------------------------------------------------------------------
# 27. Restore your XFCE panel + Geany config
# ---------------------------------------------------------------------------
# HOW TO SET THIS UP (run this once, on your CURRENT working machine, before
# you reuse this script for a fresh install):
#
#   mkdir -p dotfiles
#   cp -r ~/.config/xfce4 dotfiles/xfce4
#   cp -r ~/.config/geany dotfiles/geany
#
# Then copy the whole folder (this script + the dotfiles/ directory next to
# it) to the new machine before running the script. xfce4/ carries your
# panel layout, launchers, and plugin settings (xfconf); geany/ carries your
# editor settings, keybindings, snippets, and any custom color scheme.
#
# This just needs to happen before you first log into XFCE — XFCE and Geany
# both read these files at session/first-launch, so there's nothing to
# "apply" afterwards, no panel restart needed.
if [[ "$DO_RESTORE_DOTFILES" == true ]]; then
    if [[ -d "$DOTFILES_DIR" ]]; then
        log "Restoring saved config from ${DOTFILES_DIR}."
        restore_config_dir "${DOTFILES_DIR}/xfce4" "$HOME/.config/xfce4"
        restore_config_dir "${DOTFILES_DIR}/geany" "$HOME/.config/geany"
    else
        log "No dotfiles/ directory found next to the script (expected ${DOTFILES_DIR}) — skipping config restore. See the comment above this section for how to create it."
    fi
fi

# ---------------------------------------------------------------------------
# 28. Cleanup
# ---------------------------------------------------------------------------
if [[ "$DO_CLEANUP" == true ]]; then
    log "Cleaning up unused packages."
    sudo apt-get autoremove -y
    sudo apt-get autoclean -y
fi

log "Post-install script finished successfully."
if [[ "$DO_DESKTOP_ENV" == true ]]; then
    log "Reboot now to reach the graphical XFCE login (sudo reboot)."
fi
