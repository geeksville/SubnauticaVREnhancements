#!/usr/bin/env bash
set -Eeuo pipefail

# Deploy the built VREnhancements.dll to the Steam Frame via scp.
#
# The DLL lands in the game's BepInEx plugins folder, replacing the previous
# build.  The game must be restarted for the change to take effect.
#
# Usage:
#   bin/deploy-mod.sh            # deploy VREnhancements/bin/Release/VREnhancements.dll
#   bin/deploy-mod.sh Debug      # deploy a specific configuration
#   bin/deploy-mod.sh /path/to/VREnhancements.dll

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FRAME_HOST="${FRAME_HOST:-frame}"
GAME_DIR_REMOTE="${GAME_DIR_REMOTE:-/home/steamos/.local/share/Steam/steamapps/common/Subnautica}"
PLUGIN_DIR_REMOTE="$GAME_DIR_REMOTE/BepInEx/plugins/VR Enhancements"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

command -v scp >/dev/null || die "scp is required"
command -v ssh >/dev/null || die "ssh is required"

case "${1:-}" in
    ""|Release|Debug)
        CONFIG="${1:-Release}"
        DLL="$REPO_ROOT/VREnhancements/bin/$CONFIG/VREnhancements.dll"
        ;;
    *)
        DLL="$1"
        ;;
esac

[[ -f "$DLL" ]] || die "DLL not found: $DLL (run bin/build-mod.sh first)"

printf 'Deploying %s -> %s:%s\n' "$DLL" "$FRAME_HOST" "$PLUGIN_DIR_REMOTE"
ssh "$FRAME_HOST" "mkdir -p '$PLUGIN_DIR_REMOTE'"
scp -q "$DLL" "$FRAME_HOST:$PLUGIN_DIR_REMOTE/VREnhancements.dll"

printf 'Deployed. Restart Subnautica on the frame for the change to take effect.\n'
