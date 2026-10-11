#!/usr/bin/env bash
set -Eeuo pipefail

# Build the VREnhancements mod DLL with the .NET SDK.
#
# The mod targets net472 and references the game's own assemblies, which are
# not in this repo.  They are fetched from the Steam Frame (ssh frame) into
# lib/ on first use, then publicized with the BepInEx AssemblyPublicizer into
# lib/publicized/ so the mod can reference private/protected members directly.
#
# Usage:
#   bin/build-mod.sh            # fetch libs if missing, publicize, build
#   bin/build-mod.sh --no-fetch # use existing lib/ without touching the frame
#   bin/build-mod.sh --clean    # remove bin/obj before building

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$REPO_ROOT/lib"
PUBLICIZED_DIR="$LIB_DIR/publicized"
PROJECT="$REPO_ROOT/VREnhancements/VREnhancements.csproj"
CONFIG="${CONFIG:-Release}"

FRAME_HOST="${FRAME_HOST:-frame}"
GAME_DIR_REMOTE="${GAME_DIR_REMOTE:-/home/steamos/.local/share/Steam/steamapps/common/Subnautica}"

# DLLs needed to compile the mod.  Game assemblies come from the frame's
# Subnautica_Data/Managed; BepInEx/Harmony from BepInEx/core.
GAME_DLLS=(
    Assembly-CSharp.dll
    Assembly-CSharp-firstpass.dll
    FMODUnity.dll
    Unity.TextMeshPro.dll
    UnityEngine.dll
    UnityEngine.AnimationModule.dll
    UnityEngine.AudioModule.dll
    UnityEngine.CoreModule.dll
    UnityEngine.InputLegacyModule.dll
    UnityEngine.ParticleSystemModule.dll
    UnityEngine.PhysicsModule.dll
    UnityEngine.TextRenderingModule.dll
    UnityEngine.UI.dll
    UnityEngine.UIModule.dll
    UnityEngine.VRModule.dll
)
CORE_DLLS=(
    0Harmony20.dll
    BepInEx.dll
)

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

command -v dotnet >/dev/null || die "dotnet is required (install dotnet-sdk-8.0)"

FETCH=1
CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --no-fetch) FETCH=0 ;;
        --clean) CLEAN=1 ;;
        *) die "unknown argument: $arg" ;;
    esac
done

fetch_libs() {
    local f
    local missing=0

    for f in "${GAME_DLLS[@]}"; do
        [[ -f "$LIB_DIR/$f" ]] || missing=1
    done
    for f in "${CORE_DLLS[@]}"; do
        [[ -f "$LIB_DIR/$f" ]] || missing=1
    done
    [[ $missing -eq 0 ]] && return 0

    command -v scp >/dev/null || die "scp is required to fetch reference DLLs from the frame"
    command -v ssh >/dev/null || die "ssh is required to fetch reference DLLs from the frame"

    printf 'Fetching reference DLLs from %s...\n' "$FRAME_HOST"
    mkdir -p "$LIB_DIR"
    for f in "${GAME_DLLS[@]}"; do
        if [[ ! -f "$LIB_DIR/$f" ]]; then
            printf '  %s\n' "$f"
            scp -q "$FRAME_HOST:$GAME_DIR_REMOTE/Subnautica_Data/Managed/$f" "$LIB_DIR/" \
                || die "failed to fetch $f (is the frame reachable? set FRAME_HOST/GAME_DIR_REMOTE)"
        fi
    done
    for f in "${CORE_DLLS[@]}"; do
        if [[ ! -f "$LIB_DIR/$f" ]]; then
            printf '  %s\n' "$f"
            scp -q "$FRAME_HOST:$GAME_DIR_REMOTE/BepInEx/core/$f" "$LIB_DIR/" \
                || die "failed to fetch $f (is the frame reachable? set FRAME_HOST/GAME_DIR_REMOTE)"
        fi
    done
}

publicize() {
    local src="$1" dst="$2"
    if [[ -f "$dst" && "$dst" -nt "$src" ]]; then
        return 0
    fi
    printf 'Publicizing %s...\n' "$(basename "$src")"
    command -v assembly-publicizer >/dev/null \
        || die "assembly-publicizer not found (dotnet tool install --global BepInEx.AssemblyPublicizer.Cli)"
    assembly-publicizer "$src" -o "$PUBLICIZED_DIR" >/dev/null
}

if [[ $FETCH -eq 1 ]]; then
    fetch_libs
fi

for f in "${GAME_DLLS[@]}"; do
    [[ -f "$LIB_DIR/$f" ]] || die "missing reference DLL lib/$f (run without --no-fetch, or copy it from the frame)"
done
for f in "${CORE_DLLS[@]}"; do
    [[ -f "$LIB_DIR/$f" ]] || die "missing reference DLL lib/$f (run without --no-fetch, or copy it from the frame)"
done

mkdir -p "$PUBLICIZED_DIR"
publicize "$LIB_DIR/Assembly-CSharp.dll" "$PUBLICIZED_DIR/Assembly-CSharp-publicized.dll"
publicize "$LIB_DIR/Assembly-CSharp-firstpass.dll" "$PUBLICIZED_DIR/Assembly-CSharp-firstpass-publicized.dll"

if [[ $CLEAN -eq 1 ]]; then
    rm -rf "$REPO_ROOT/VREnhancements/bin" "$REPO_ROOT/VREnhancements/obj"
fi

printf 'Building %s...\n' "$CONFIG"
dotnet build "$PROJECT" -c "$CONFIG" --nologo

OUT="$REPO_ROOT/VREnhancements/bin/$CONFIG/VREnhancements.dll"
[[ -f "$OUT" ]] || die "build did not produce $OUT"
printf '\nBuilt: %s\n' "$OUT"
