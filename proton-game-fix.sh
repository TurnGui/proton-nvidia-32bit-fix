#!/usr/bin/env bash
#
# proton-game-fix.sh
#
# Installs Windows runtime libraries (Visual C++ Redistributables, .NET, etc.)
# into a specific Steam game's Proton prefix using protontricks. This is the
# standard fix for older Windows games that crash on launch, fail to start,
# or hang at the launcher when running through Proton on Linux.
#
# Use this AFTER nvidia-32bit-fix.sh if you have an NVIDIA GPU. If your game
# is still broken after the GPU fix, this is almost always the next step.
#
# What it does:
#   1. Installs protontricks (via Flatpak) if not already present.
#   2. Auto-detects your Steam install location.
#   3. Lets you search your installed games by name (no need to find App ID
#      manually).
#   4. Suggests known-good components for popular games, or a generic set
#      otherwise.
#   5. Runs protontricks to install them into the game's prefix.
#
# What it does NOT do:
#   - Touch any system files outside ~/.steam/ and ~/.local/share/flatpak/.
#   - Modify Proton itself, kernel modules, or your driver.
#   - Run as root (it shouldn't need to).
#
# Run with --dry-run to see what it would do without doing anything.
# Run with --help for usage info.
#
# License: public domain. Read the script before running it.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

if [[ -t 1 ]]; then
    readonly C_RED=$'\033[0;31m'
    readonly C_GREEN=$'\033[0;32m'
    readonly C_YELLOW=$'\033[0;33m'
    readonly C_BLUE=$'\033[0;34m'
    readonly C_BOLD=$'\033[1m'
    readonly C_RESET=$'\033[0m'
else
    readonly C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_BOLD="" C_RESET=""
fi

DRY_RUN=0
ASSUME_YES=0
STEAM_DIR=""
declare -a STEAMAPPS_DIRS=()

info()  { echo "${C_BLUE}[info]${C_RESET} $*"; }
ok()    { echo "${C_GREEN}[ ok ]${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}[warn]${C_RESET} $*" >&2; }
err()   { echo "${C_RED}[err ]${C_RESET} $*" >&2; }
step()  { echo; echo "${C_BOLD}==> $*${C_RESET}"; }

run() {
    echo "    ${C_BOLD}\$${C_RESET} $*"
    if [[ $DRY_RUN -eq 0 ]]; then
        "$@"
    fi
}

usage() {
    cat <<EOF
${C_BOLD}${SCRIPT_NAME}${C_RESET} — install Windows runtimes into a Steam game's Proton prefix

Usage:
  ${SCRIPT_NAME} [--dry-run] [--yes] [--help]

Options:
  --dry-run   Show every command that would be run, but do not execute
              anything that modifies the system.
  --yes       Skip confirmation prompts. You should still --dry-run first.
  --help      Show this help.

This script is interactive. It'll ask you which game you want to fix and
suggest the right components for it.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --yes|-y)  ASSUME_YES=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) err "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

if [[ $DRY_RUN -eq 1 ]]; then
    warn "DRY RUN — no changes will be made to the system."
fi

if [[ ${EUID} -eq 0 ]]; then
    err "Do not run this script as root or with sudo."
    err "Protontricks runs in your user account, not root."
    exit 1
fi

# Known-good component lists for popular games. Each entry is the App ID
# followed by the components separated by spaces. These are based on what
# people on ProtonDB consistently report as working. If a game isn't here,
# the user gets a sensible default.
#
# Format: "<appid>|<game name>|<components>"
#
# Keep this list relatively short — only games where we're confident the
# components are right. Better to fall back to the generic set than to
# install the wrong thing.
declare -a KNOWN_GAMES=(
    "34330|Total War: SHOGUN 2|d3dcompiler_47 vcrun2010 vcrun2013 vcrun2019 dotnet40"
    "10500|Empire: Total War|d3dcompiler_47 vcrun2008 vcrun2010 vcrun2019 dotnet40"
    "34030|Napoleon: Total War|d3dcompiler_47 vcrun2008 vcrun2010 vcrun2019 dotnet40"
    "4700|Medieval II: Total War|vcrun2005 vcrun2008 d3dx9"
    "72850|The Elder Scrolls V: Skyrim|vcrun2010 vcrun2013 d3dcompiler_47 d3dx9"
    "22380|Fallout: New Vegas|vcrun2008 vcrun2010 d3dx9 xact"
    "22300|Fallout 3|vcrun2005 vcrun2008 d3dx9 xact"
    "22320|Fallout 3 GOTY|vcrun2005 vcrun2008 d3dx9 xact"
    "47810|Dragon Age: Origins|vcrun2008 vcrun2010 d3dx9 dotnet35"
    "12210|Grand Theft Auto IV|vcrun2008 vcrun2010 d3dx9 xact"
    "220|Half-Life 2|d3dcompiler_47"
    "320|Half-Life 2: Deathmatch|d3dcompiler_47"
    "380|Half-Life 2: Episode One|d3dcompiler_47"
    "420|Half-Life 2: Episode Two|d3dcompiler_47"
    "70|Half-Life|d3dcompiler_47"
    "8870|BioShock|vcrun2008 d3dx9"
    "409710|BioShock Remastered|vcrun2019 d3dcompiler_47"
    "8980|BioShock 2|vcrun2008 d3dx9"
    "21660|Plants vs. Zombies: GOTY|vcrun2010"
)

# Generic components that work for most older 32-bit Windows games.
# Used when the game isn't in KNOWN_GAMES and the user opts for "generic".
readonly GENERIC_COMPONENTS="d3dcompiler_47 vcrun2010 vcrun2013 vcrun2019 dotnet40"

step "Step 1/4: Locate your Steam installation"

# Try common locations in order. The Mint/Debian one is unusual; the
# others are standard.
for candidate in \
    "$HOME/.steam/debian-installation" \
    "$HOME/.local/share/Steam" \
    "$HOME/.steam/steam" \
    "$HOME/.steam/root" \
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
do
    if [[ -d "${candidate}/steamapps" ]]; then
        STEAM_DIR="$candidate"
        STEAMAPPS_DIRS+=("${candidate}/steamapps")
        break
    fi
done

if [[ -z "$STEAM_DIR" ]]; then
    err "Could not find a Steam installation in any of the usual locations."
    err "Tried:"
    err "  ~/.steam/debian-installation"
    err "  ~/.local/share/Steam"
    err "  ~/.steam/steam"
    err "  ~/.steam/root"
    err "  ~/.var/app/com.valvesoftware.Steam/data/Steam (flatpak)"
    err "If your Steam is somewhere else, this script can't help."
    exit 1
fi
ok "Steam found at: ${STEAM_DIR}"

# Steam libraries can be on other drives. The list of extra library folders
# lives in libraryfolders.vdf. Parse paths out of it (loose grep — that VDF
# format is annoying but the "path" entries are predictable).
LIBRARY_VDF="${STEAM_DIR}/steamapps/libraryfolders.vdf"
if [[ -f "$LIBRARY_VDF" ]]; then
    while IFS= read -r extra; do
        if [[ -d "${extra}/steamapps" && "${extra}/steamapps" != "${STEAM_DIR}/steamapps" ]]; then
            STEAMAPPS_DIRS+=("${extra}/steamapps")
        fi
    done < <(grep -oE '"path"[[:space:]]+"[^"]+"' "$LIBRARY_VDF" | sed -E 's/.*"([^"]+)"$/\1/')
fi

if [[ ${#STEAMAPPS_DIRS[@]} -gt 1 ]]; then
    info "Also checking ${#STEAMAPPS_DIRS[@]} additional library folder(s)."
fi

step "Step 2/4: Make sure protontricks is available"

# protontricks-flatpak is the recommended way (handles new Steam appinfo
# format that the apt version of protontricks chokes on). We always go
# through Flatpak here for that reason.
PROTONTRICKS_CMD=""

if command -v flatpak >/dev/null 2>&1; then
    if flatpak list --app --columns=application 2>/dev/null | grep -q '^com.github.Matoking.protontricks$'; then
        ok "protontricks (Flatpak) is already installed."
        PROTONTRICKS_CMD="flatpak run --env=STEAM_DIR=${STEAM_DIR} com.github.Matoking.protontricks"
    else
        info "protontricks not installed via Flatpak. We'll install it now."
        info "(The apt version of protontricks doesn't work with current Steam"
        info " versions — Flatpak is the only reliable option.)"

        if [[ $ASSUME_YES -eq 0 ]]; then
            read -rp "Install protontricks via Flatpak now? [Y/n] " ans
            case "${ans,,}" in
                n|no) err "Aborted by user."; exit 1 ;;
                *) : ;;
            esac
        fi

        run flatpak install --user -y flathub com.github.Matoking.protontricks

        # Grant access to Steam directories so protontricks can see your library.
        # Without these, it errors with "No Steam installation was selected".
        run flatpak override --user --filesystem="$HOME/.steam" com.github.Matoking.protontricks
        run flatpak override --user --filesystem="$HOME/.local/share/Steam" com.github.Matoking.protontricks

        PROTONTRICKS_CMD="flatpak run --env=STEAM_DIR=${STEAM_DIR} com.github.Matoking.protontricks"
        ok "protontricks installed."
    fi
else
    err "Flatpak is not installed. Install it first:"
    err "    sudo apt install flatpak"
    err "Then re-run this script."
    exit 1
fi

step "Step 3/4: Find the game you want to fix"

# Build a list of installed games from appmanifest_*.acf files.
# Format we want: "appid|name"
declare -a INSTALLED_GAMES=()

for steamapps in "${STEAMAPPS_DIRS[@]}"; do
    while IFS= read -r manifest; do
        appid=$(grep -oE '"appid"[[:space:]]+"[0-9]+"' "$manifest" 2>/dev/null \
                | head -n1 | grep -oE '[0-9]+' || true)
        name=$(grep -oE '"name"[[:space:]]+"[^"]+"' "$manifest" 2>/dev/null \
               | head -n1 | sed -E 's/.*"([^"]+)"$/\1/' || true)
        if [[ -n "$appid" && -n "$name" ]]; then
            INSTALLED_GAMES+=("${appid}|${name}")
        fi
    done < <(find "$steamapps" -maxdepth 1 -name "appmanifest_*.acf" -type f 2>/dev/null)
done

if [[ ${#INSTALLED_GAMES[@]} -eq 0 ]]; then
    err "No installed games found in your Steam library."
    err "Make sure the game is actually installed (not just owned) before running this."
    exit 1
fi
ok "Found ${#INSTALLED_GAMES[@]} installed game(s)."

# Ask the user for a search term and filter. Loop until they pick something
# or explicitly quit — typos and empty queries shouldn't kill the script.
GAME_APPID=""
GAME_NAME=""

while [[ -z "$GAME_APPID" ]]; do
    echo
    read -rp "Type part of the game name (or 'q' to quit): " query

    # Quit shortcuts
    case "${query,,}" in
        q|quit|exit) info "Aborted by user."; exit 0 ;;
    esac

    if [[ -z "$query" ]]; then
        warn "Empty query. Try typing part of a game name, e.g. 'shogun'."
        continue
    fi

    query_lower="${query,,}"
    declare -a MATCHES=()
    for entry in "${INSTALLED_GAMES[@]}"; do
        name="${entry##*|}"
        name_lower="${name,,}"
        if [[ "$name_lower" == *"$query_lower"* ]]; then
            MATCHES+=("$entry")
        fi
    done

    if [[ ${#MATCHES[@]} -eq 0 ]]; then
        warn "No games in your library match '$query'. Try a shorter or different term."
        continue
    fi

    if [[ ${#MATCHES[@]} -eq 1 ]]; then
        GAME_APPID="${MATCHES[0]%%|*}"
        GAME_NAME="${MATCHES[0]##*|}"
        ok "Match: ${GAME_NAME} (App ID ${GAME_APPID})"
        break
    fi

    # Multiple matches — show numbered list and let the user pick.
    # If they enter something invalid, loop back to the search prompt
    # rather than exit.
    echo
    echo "Multiple matches found:"
    i=1
    for entry in "${MATCHES[@]}"; do
        appid="${entry%%|*}"
        name="${entry##*|}"
        printf "  %d. %s (App ID %s)\n" "$i" "$name" "$appid"
        i=$((i+1))
    done
    echo
    read -rp "Select a number (or press Enter to search again): " choice

    if [[ -z "$choice" ]]; then
        continue
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 || $choice -gt ${#MATCHES[@]} ]]; then
        warn "Invalid selection. Searching again."
        continue
    fi
    GAME_APPID="${MATCHES[$((choice-1))]%%|*}"
    GAME_NAME="${MATCHES[$((choice-1))]##*|}"
    ok "Selected: ${GAME_NAME} (App ID ${GAME_APPID})"
done

step "Step 4/4: Choose the components to install"

# Look up the game in KNOWN_GAMES
KNOWN_COMPONENTS=""
for entry in "${KNOWN_GAMES[@]}"; do
    known_appid="${entry%%|*}"
    if [[ "$known_appid" == "$GAME_APPID" ]]; then
        KNOWN_COMPONENTS="${entry##*|}"
        break
    fi
done

CHOSEN_COMPONENTS=""

if [[ -n "$KNOWN_COMPONENTS" ]]; then
    info "${GAME_NAME} is in my known-good list."
    echo "Recommended components: ${C_BOLD}${KNOWN_COMPONENTS}${C_RESET}"
    echo
    echo "Options:"
    echo "  1. Use the recommended components (this is what fixes most installs)"
    echo "  2. Enter your own component list (use this if you've checked ProtonDB"
    echo "     and they recommend something different)"
    echo "  3. Cancel"
    echo
    read -rp "Choice [1]: " choice
    choice="${choice:-1}"

    case "$choice" in
        1) CHOSEN_COMPONENTS="$KNOWN_COMPONENTS" ;;
        2)
            read -rp "Enter components separated by spaces: " CHOSEN_COMPONENTS
            CHOSEN_COMPONENTS="${CHOSEN_COMPONENTS// /  }" # collapse multi-space
            CHOSEN_COMPONENTS="$(echo "$CHOSEN_COMPONENTS" | xargs)" # trim
            ;;
        3) info "Cancelled by user."; exit 0 ;;
        *) err "Invalid choice."; exit 1 ;;
    esac
else
    info "${GAME_NAME} isn't in my known-good list."
    echo
    echo "Options:"
    echo "  1. Try the generic set: ${C_BOLD}${GENERIC_COMPONENTS}${C_RESET}"
    echo "     (covers most older 32-bit Windows games)"
    echo "  2. Enter your own component list"
    echo "     (recommended: check https://protondb.com first to see what"
    echo "     others have used for this game)"
    echo "  3. Cancel"
    echo
    read -rp "Choice [1]: " choice
    choice="${choice:-1}"

    case "$choice" in
        1) CHOSEN_COMPONENTS="$GENERIC_COMPONENTS" ;;
        2)
            read -rp "Enter components separated by spaces: " CHOSEN_COMPONENTS
            CHOSEN_COMPONENTS="$(echo "$CHOSEN_COMPONENTS" | xargs)"
            ;;
        3) info "Cancelled by user."; exit 0 ;;
        *) err "Invalid choice."; exit 1 ;;
    esac
fi

if [[ -z "$CHOSEN_COMPONENTS" ]]; then
    err "No components selected."
    exit 1
fi

step "Plan"
cat <<EOF
Game:       ${C_BOLD}${GAME_NAME}${C_RESET} (App ID ${GAME_APPID})
Prefix:     ${STEAM_DIR}/steamapps/compatdata/${GAME_APPID}/pfx/
Components: ${C_BOLD}${CHOSEN_COMPONENTS}${C_RESET}

This will run protontricks to install the listed components into the game's
Proton prefix. It does NOT modify other games or system files.

The install can take 5–10 minutes. You'll see lots of console output and
maybe Windows installer windows flicker by — let it finish. When you see
"wineserver -w" at the end, that's normal; it's just shutting down cleanly.

${C_YELLOW}IMPORTANT${C_RESET}: make sure ${GAME_NAME} is NOT running in Steam (and isn't
showing as 'running' in your library). Protontricks will fail if it is.

EOF

if [[ $DRY_RUN -eq 0 && $ASSUME_YES -eq 0 ]]; then
    read -rp "Proceed? [y/N] " ans
    case "${ans,,}" in
        y|yes) : ;;
        *) info "Aborted by user. Nothing was changed."; exit 0 ;;
    esac
fi

step "Running protontricks…"

# We split CHOSEN_COMPONENTS on whitespace into separate args.
# shellcheck disable=SC2086
run $PROTONTRICKS_CMD "$GAME_APPID" -q $CHOSEN_COMPONENTS

step "Done."
ok "Components installed into ${GAME_NAME}'s prefix."

cat <<EOF

${C_BOLD}Try launching the game now.${C_RESET}

If a popup appears titled something like "xalia.exe — .NET Framework v4.8
required", click ${C_BOLD}No${C_RESET} — it's a cosmetic GE-Proton accessibility
tool, not the game, and the game will continue without it.

If the game still doesn't run:
  - Check https://protondb.com for ${GAME_NAME} reports.
  - Try a different Proton version (Properties → Compatibility in Steam).
    GE-Proton (install via ProtonUp-Qt) often works for older games.
  - If you have an NVIDIA GPU and haven't run nvidia-32bit-fix.sh yet,
    that's the most likely missing piece.

To re-run with different components later, just run this script again.
EOF
