# Subnautica VR Performance on Steam Frame

> Status: investigation notes (2026-10-10, updated 2026-10-11). Everything
> below was gathered live from the device over SSH (`ssh frame`) while the game
> was installed and had been run at least once. Claims are marked
> **[verified]** (read directly from the device) or **[hypothesis]** (inferred
> from the stack, needs a test).

## TL;DR

Subnautica is a **Windows/PE game** running on an **ARM** Steam Frame through a
four-layer translation stack:

```
Subnautica.exe (x86-64, D3D11)
  └─ FEX-Emu        (x86 → ARM JIT, CPU translation)
       └─ Wine/Proton 11.0 (ARM64)
            └─ DXVK v2.7.1   (D3D11 → Vulkan)
                 └─ Turnip    (Vulkan → Adreno 750)
```

The game was **capped at 45 FPS by its own in-game setting**
(`Graphics/FrameRate = 45`), and SteamVR had **auto-scaled the render target
down to 64%** (1728×1728/eye) because the GPU can't keep up at full res.

**Update (2026-10-11):** the 45 FPS cap has been **removed** by the mod
(3.1 ✅), and the game is now confirmed **GPU-bound in-game** — not CPU-bound.
SteamVR's perf criteria shows ~26 ms frame time with **GPU time ≈ frame time**
(~25 ms) and CPU time only ~10–13 ms. Disabling FEX TSO + enabling multiblock
(3.5) made **no measurable difference**, which is consistent with a GPU
bottleneck. The remaining levers are **reducing GPU cost** (render scale,
post-processing, single-pass stereo).

---

## 1. The stack, as measured on the device

### Hardware
- **CPU**: ARM big.LITTLE — 2× Cortex-A520 + 5× Cortex-A720, 8 cores, up to
  2.27 GHz. **[verified]** (`lscpu`)
- **RAM**: 15 GiB total, ~8.5 GiB available. **[verified]** (`free -h`)
- **GPU**: Qualcomm **Adreno 750**, exposed as `Turnip Adreno (TM) 750` via the
  open-source Mesa Turnip Vulkan driver. **[verified]** (Unity `Player.log`,
  SteamVR `steamvr.vrsettings`)
- **HMD**: Steam Frame, 90 Hz refresh (`preferredRefreshRate: 90`).
  **[verified]** (`steamvr.vrsettings`)

### Software
- **OS**: SteamOS (holo, Arch-based), kernel 6.18 aarch64. **[verified]**
- **SteamVR**: runs **natively on ARM64** (`/opt/steamvr/bin/linuxarm64/...`).
  **[verified]** (`ps aux`)
- **Game**: Subnautica, Unity **2019.4.36f1**, Mono, **Direct3D 11** renderer.
  **[verified]** (`Player.log`: `graphicsDeviceType = Direct3D11`,
  `graphicsDeviceVersion = Direct3D 11.0 [level 11.1]`)
- **Compatibility**: Proton **11.0-100 (ARM64)** + **FEX-Emu** x86→ARM JIT.
  **[verified]** (`compatdata/264710/version`, `config_info`)
- **DXVK**: **v2.7.1** (D3D11→Vulkan). **[verified]** (`dxvk/version`)
- **Mod**: BepInEx 5.4.23.5 + VR Enhancements 3.2.1, loads and patches
  successfully (`[VR Enhancements] Patched for device: OpenVR`).
  **[verified]** (`BepInEx/LogOutput.log`)

### Current in-game settings (decoded from `options.bin`) **[verified]**
| Setting | Value | Notes |
|---|---|---|
| `Graphics/FrameRate` | **45** | **This is the FPS cap.** |
| `VR/RenderScale` | 1.0 | Game's own per-eye render scale |
| `Graphics/Quality` | 1 (Medium) | Unity quality level |
| `Graphics/Bloom` | 1 (on) | |
| `Graphics/BloomLensDirt` | 1 (on) | |
| `Graphics/DepthOfField` | 1 (on) | |
| `Graphics/Dithering` | 1 (on) | |
| `Graphics/AntiAliasingMode` | 0 (off) | |
| `Graphics/AntiAliasingQuality` | 1 | |
| `Graphics/AmbientOcclusionQuality` | 1 | |
| `Graphics/ScreenSpaceReflectionsQuality` | **2** | Expensive |
| `Graphics/MotionBlurQuality` | 0 (off) | |
| `Graphics/ColorGrading` | 0 (off) | |

### SteamVR auto-resolution **[verified]**
`steamvr.vrsettings` → `GpuSpeed.gpuSpeedRenderTargetScale = 0.64`. SteamVR has
already dropped the per-eye render target to **64%** (1728×1728/eye, from the
log: `Created remote Vulkan image ... dimensions 1728 x 1728`). This is
SteamVR's automatic resolution scaling reacting to the GPU being overloaded.

---

## 2. Why you see ~45 FPS

There are **three independent reasons**, in order of impact:

### 2.1 The game was hard-capped at 45 FPS by its own setting **[verified, fixed]**
`Graphics/FrameRate = 45` in `options.bin`. Subnautica applies this to
`Application.targetFrameRate`, which caps the render loop. In VR this means the
game submits at most 45 frames/sec to SteamVR, which then has to reproject
(motion-smooth) the other 45 of the 90 Hz.

**Fixed (2026-10-11):** the mod now forces `Application.targetFrameRate = -1`
(unlimited) while VR is active (see 3.1). Verified in `Player.log`:
`[VR Enhancements] Removed FPS cap: targetFrameRate = -1`.

### 2.2 The GPU is the real bottleneck in-game **[verified, corrected 2026-10-11]**
SteamVR's perf criteria (`~/.local/share/Steam/logs/perfcriteria.txt`) shows
the columns `frame time(ms), cpu time(ms), gpu time(ms), #reprojected`:

| Context | frame | cpu | gpu | #reproj |
|---|---|---|---|---|
| Main menu / loading | ~7.5 | ~7.5 | ~2.7 | 0 |
| In-game (both sessions) | ~26 | ~10–13 | **~26** | 1 |

In-game, **GPU time ≈ frame time (~26 ms ≈ 38 FPS)** while CPU time is only
~10–13 ms. The game is **GPU-bound**, not CPU-bound. This is why removing the
FPS cap didn't raise the number: the GPU genuinely can't produce more than
~40 FPS at the current render scale, and SteamVR reprojects the rest of the
90 Hz.

### 2.3 The CPU translation tax is real but NOT the current bottleneck **[verified, corrected 2026-10-11]**
Every game-logic/CPU instruction runs through FEX's x86→ARM JIT, and FEX
defaults to **TSO (Total Store Order)** memory-ordering emulation, which is
slower than native ARM ordering. However, a controlled experiment on
2026-10-11 (launch options `STEAM_FEX_TSOENABLED=0 STEAM_FEX_MULTIBLOCK=1`)
showed **no measurable improvement** — frame time stayed ~26 ms and
reprojection stayed ~81%. This is consistent with the GPU-bound diagnosis:
optimizing the CPU layer can't help when the GPU is the limit.

### 2.4 The game renders in the most expensive stereo mode **[verified]**
Unity log: `Created eye textures with a "separate" layout. The "multi-pass"
stereo mode will be used.` Multi-pass renders the whole scene **twice** (once
per eye). Single-pass instanced renders both eyes in one pass — roughly halving
vertex/draw-call cost. Subnautica ships with multi-pass, and switching it is
risky (custom shaders must support instancing), but it's the biggest potential
GPU win.

---

## 3. Possible solutions

Ranked by (expected gain × ease × safety). Items marked **[mod]** are things we
can implement in this repo; items marked **[config]** are device/Steam settings.

### 3.1 Remove the 45 FPS cap — **[mod], biggest & safest win** ✅ implemented
Patch the game so that when VR is active, `Application.targetFrameRate` is set
to the HMD refresh rate (90) or `-1` (unlimited) instead of the 45 from
`Graphics/FrameRate`.

- **Where**: `VREnhancements/FrameRateFix.cs` — a `LateUpdate` hook in
  `MainPatcher` forces `Application.targetFrameRate` while `XRSettings` is
  active, and a `GameSettings.SerializeVRSettings` postfix re-applies it after
  settings (re)load.
- **Config** (`VREnhancements.cfg` → `[Performance]`):
  - `removeFPSCap = true` (default) — enable/disable the override.
  - `targetFPS = 0` (default) — 0 = unlimited (`-1`), 90 = HMD refresh rate,
    any other value used as-is.
- **Expected gain**: if the GPU can actually do more than 45, this directly
  raises render FPS. Even if it can't, it removes the artificial ceiling and
  lets SteamVR's reprojection work from a higher base.
- **Risk**: low. Worst case the game renders at whatever the GPU can do.
- **Caveat**: the game re-applies the cap on settings load; the
  `SerializeVRSettings` postfix handles that. If the game re-applies it every
  frame, the `LateUpdate` hook covers that too.

### 3.2 Lower per-eye render resolution — **[config] + [mod]**
- **[config]** SteamVR per-app resolution override for app 264710 (set
  `steam.app.264710` render multiplier below the current 0.64 auto value, e.g.
  0.5–0.6). This is the fastest way to buy GPU headroom.
- **[mod]** Expose the game's own `VR/RenderScale` (currently 1.0) as a
  configurable value in the mod's `VREnhancements.cfg` and clamp it lower.
- **Expected gain**: resolution scales roughly linearly with fill-rate cost.
  0.64 → 0.5 is ~40% fewer pixels/eye.
- **Risk**: low; just blurrier. In VR this is often the best trade.

### 3.3 Disable expensive post-processing — **[config] + [mod]**
From `options.bin`, the expensive ones currently on are:
- `ScreenSpaceReflectionsQuality = 2` (SSR — very expensive, especially at
  VR resolutions)
- `AmbientOcclusionQuality = 1`
- `DepthOfField = 1`
- `Bloom = 1`, `BloomLensDirt = 1`

- **[config]** Turn these off in the in-game Options menu.
- **[mod]** Add a "VR Performance" toggle in the mod that forces these off
  (and restores them on exit) via `GameSettings`/`QualitySettings` patches.
- **Expected gain**: SSR and AO are the big ones; expect meaningful GPU relief.
- **Risk**: low; visual quality only.

### 3.4 Try single-pass instanced stereo — **[mod], biggest GPU win, risky] ❌ failed experiment**
Patch `XRSettings.stereoRenderingMode = SinglePassInstanced` at VR init.

- **Attempted 2026-10-11**: implemented `SinglePassStereo.cs` which hooked the
  `XRSettings.stereoRenderingMode` getter to report `SinglePassInstanced` and
  reloaded the XR device (`XRSettings.LoadDeviceByName`) to re-initialize the
  rendering path. Config-gated (`singlePassStereo = true`, default ON).
- **Result**: **FAILED**. The game hung before reaching the title screen on
  both launch attempts (had to be manually killed). `Player.log` showed
  `[VR Enhancements] Patched for device: OpenVR` but the
  `Single-pass stereo enabled` message never appeared — the
  `XRSettings.LoadDeviceByName()` device reload hangs Unity mid-initialization.
- **Root cause**: Unity 2019.4 exposes `XRSettings.stereoRenderingMode` as
  **get-only** (no managed setter, no native setter, no exported function).
  The stereo mode is baked into the build's XR settings and fixed at device
  load. Reloading the device to change it is not viable.
- **Verdict**: **not viable in this Unity version**. Code removed. Do not
  retry without a fundamentally different approach (e.g. patching the native
  rendering path, which is out of scope for a BepInEx mod).

### 3.5 Reduce FEX CPU tax — **[config] — tested, no measurable gain**
FEX supports `STEAM_FEX_TSOENABLED` and `STEAM_FEX_MULTIBLOCK` (see
`FEX-Emu/fex-compat-tool`). TSO emulation is the big CPU cost.

- Try Steam launch options:
  ```
  STEAM_FEX_TSOENABLED=0 STEAM_FEX_MULTIBLOCK=1 WINEDLLOVERRIDES="winhttp=n,b" %command%
  ```
- **Tested 2026-10-11**: no measurable improvement. Frame time stayed ~26 ms,
  reprojection stayed ~81% (vrserver: `NumReprojected 7081 / 8709 presents`).
  Consistent with the GPU-bound diagnosis (2.2) — the CPU isn't the limit.
- **Risk**: TSO off can cause rare crashes/glitches in some games — test
  carefully. Multiblock is generally safe and helps JIT throughput.
- **Verdict**: keep the options if you like (they don't hurt), but don't expect
  FPS gains. Revisit only if a future change makes the game CPU-bound (e.g.
  single-pass stereo cuts GPU time below CPU time).

### 3.6 Reduce per-frame overhead in the mod itself — **[mod]**
On a JIT-translated CPU, per-frame managed allocations and `GetComponent`
calls are comparatively expensive. The mod has several hot paths:
- `VehicleHUDManager.Update()` — runs every frame, does multiple
  `Quaternion.LookRotation` + transform ops.
- `UIElementsFixes.Player_Update_Patch` — every frame, multiple
  `GetComponent<UIFader>()` calls and `Player.main` lookups.
- `UIFader.Update()` — every frame.
- `HandReticle.LateUpdate` patch — every frame.

These are small individually but add up under FEX. A "performance pass" that
caches components/transforms and skips work when nothing changed is a
low-risk, low-gain cleanup. **Note**: since the game is GPU-bound (2.2), this
is lower priority than 3.2/3.3.

### 3.7 Shader-cache warm-up — **[config]**
Mesa shader cache is only ~19 MB and no DXVK cache was found, so the game is
likely still compiling shaders on first encounters (stutter). Options:
- Play through the game once to warm caches (they persist).
- Consider a `dxvk.conf` with `dxvk.numCompilerThreads` tuning (DXVK 2.x
  compiles async by default; the main lever is just letting the cache build).
- **Expected gain**: removes stutter, not average FPS.

---

## 4. Recommended next steps (in order)

1. **Remove the 45 FPS cap in the mod** (3.1) — ✅ done 2026-10-11. Verified in
   `Player.log`: `targetFrameRate = -1`.
2. **Measure** with the cap removed — ✅ done. SteamVR perf criteria shows the
   game is **GPU-bound in-game** (~26 ms frame, GPU ~26 ms, CPU ~10–13 ms).
3. **GPU-bound confirmed** → apply 3.2 (lower render scale) and 3.3 (disable
   SSR/AO/DOF). (3.4 single-pass was attempted and failed — see 3.4.)
4. ~~If **CPU-bound**: apply 3.5 (FEX TSO off / multiblock) and 3.6 (mod
   hot-path cleanup).~~ — 3.5 tested, no gain. 3.6 is low priority while
   GPU-bound.
5. Warm shader caches (3.7) regardless.

## 5. What I can implement in this repo

- **3.1** ✅ done — `FrameRateFix.cs` forces `Application.targetFrameRate` to
  unlimited (or 90) while VR is active, with `[Performance]` config entries.
  Build with `bin/build-mod.sh`, deploy with `bin/deploy-mod.sh`.
- **3.2** — expose `VR/RenderScale` in `VREnhancements.cfg`. **Next best lever**
  now that the game is confirmed GPU-bound.
- **3.3** — a "VR Performance" config toggle that disables SSR/AO/DOF/Bloom.
  Also high value while GPU-bound.
- **3.4** ❌ failed experiment (2026-10-11) — single-pass stereo is **not
  viable** in Unity 2019.4: `stereoRenderingMode` is get-only and reloading
  the XR device hangs the game. Code removed.
- **3.6** — a hot-path cleanup pass (cache components, reduce per-frame work).
  Low priority while GPU-bound.

Items 3.5 (tested, no gain) and 3.7 are device/Steam settings — documented
above with exact commands, but not code changes to this repo.
