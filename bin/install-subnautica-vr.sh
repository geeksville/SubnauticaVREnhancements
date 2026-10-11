#!/usr/bin/env bash
set -Eeuo pipefail

# Install BepInEx and Subnautica VR Enhancements into Steam app 264710.
#
# Subnautica is distributed as a Windows/PE game on SteamOS and normally runs
# through Proton.  In that case this script deliberately installs the Windows
# BepInEx build and prints the required Steam launch option.  Native Linux
# Unity games use the Linux build and run_bepinex.sh instead.

readonly APP_ID=264710
readonly BEPINEX_VERSION=5.4.23.5
readonly VR_VERSION=3.2.2
readonly VR_ASSET="VR.Enhancements.v${VR_VERSION}.zip"
readonly WORK_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/subnautica-vr-install"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

command -v wget >/dev/null || die "wget is required"
command -v unzip >/dev/null || die "unzip is required"

find_game_dir() {
    local manifest installdir library

    if [[ -n "${SUBNAUTICA_DIR:-}" ]]; then
        printf '%s\n' "$SUBNAUTICA_DIR"
        return
    fi

    # Searching manifests handles the default Steam location and additional
    # libraries mounted on Steam Deck/SteamOS.  The appmanifest contains the
    # directory name; its parent is the library's steamapps directory.
    while IFS= read -r manifest; do
        installdir=$(sed -n 's/^[[:space:]]*"installdir"[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "$manifest" | head -n 1)
        [[ -n "$installdir" ]] || continue
        library=$(dirname "$manifest")
        printf '%s/common/%s\n' "$library" "$installdir"
        return
    done < <(
        find \
            "$HOME/.local/share/Steam" \
            "$HOME/.steam/steam" \
            "/run/media/$USER" \
            "/mnt" \
            -type f -name "appmanifest_${APP_ID}.acf" -print 2>/dev/null
    )

    return 1
}

GAME_DIR=$(find_game_dir) || die "could not find Steam app ${APP_ID}; set SUBNAUTICA_DIR=/path/to/Subnautica"
[[ -d "$GAME_DIR" ]] || die "game directory does not exist: $GAME_DIR"

if [[ -f "$GAME_DIR/Subnautica.exe" ]]; then
    # SteamOS/Proton: the game binary is Windows PE, so use BepInEx's Windows
    # x64 release.  This is the same directory installation described by the
    # BepInEx documentation, with Proton's DLL loader enabled at launch.
    BepInEx_URL="https://github.com/BepInEx/BepInEx/releases/download/v${BEPINEX_VERSION}/BepInEx_win_x64_${BEPINEX_VERSION}.zip"
    LAUNCH_HINT='WINEDLLOVERRIDES="winhttp=n,b" %command%'
elif [[ -f "$GAME_DIR/Subnautica" ]]; then
    BepInEx_URL="https://github.com/BepInEx/BepInEx/releases/download/v${BEPINEX_VERSION}/BepInEx_linux_x64_${BEPINEX_VERSION}.zip"
    LAUNCH_HINT='./run_bepinex.sh %command%'
else
    die "could not identify a supported Subnautica executable in $GAME_DIR"
fi

mkdir -p "$WORK_DIR"
BE_ZIP="$WORK_DIR/BepInEx_${BEPINEX_VERSION}.zip"
VR_ZIP="$WORK_DIR/$VR_ASSET"

printf 'Installing into: %s\n' "$GAME_DIR"
printf 'Downloading BepInEx %s...\n' "$BEPINEX_VERSION"
wget -q --show-progress -O "$BE_ZIP" "$BepInEx_URL"
printf 'Downloading VR Enhancements %s...\n' "$VR_VERSION"
wget -q --show-progress -O "$VR_ZIP" \
    "https://github.com/IWhoI/SubnauticaVREnhancements/releases/download/v${VR_VERSION}/${VR_ASSET}"

printf 'Extracting BepInEx...\n'
unzip -oq "$BE_ZIP" -d "$GAME_DIR"

VR_PLUGIN_DIR="$GAME_DIR/BepInEx/plugins/VR Enhancements"
mkdir -p "$VR_PLUGIN_DIR"
unzip -ojq "$VR_ZIP" '*/VREnhancements.dll' -d "$VR_PLUGIN_DIR"
[[ -s "$VR_PLUGIN_DIR/VREnhancements.dll" ]] || die 'VR Enhancements DLL was not found in the archive'

printf '\nInstallation complete.\n'
printf 'BepInEx files: %s\n' "$GAME_DIR/BepInEx"
printf 'VR plugin:     %s\n' "$VR_PLUGIN_DIR/VREnhancements.dll"
printf 'Steam launch option (required): %s\n' "$LAUNCH_HINT"
