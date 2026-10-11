# Subnautica VR Performance on Steam Frame

> Status: investigation notes (2026-10-10). Everything below was gathered live
> from the device over SSH (`ssh frame`) while the game was installed and had
> been run at least once. Claims are marked **[verified]** (read directly from
> the device) or **[hypothesis]** (inferred from the stack, needs a test).

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

The game is currently **capped at 45 FPS by its own in-game setting**
(`Graphics/FrameRate = 45`), and SteamVR has already **auto-scaled the render
target down to 64%** (1728×1728/eye) because the GPU can't keep up at full res.
The single biggest, safest win is to **remove the 45 FPS cap** so the game can
render at the HMD's 90 Hz. After that, the next lever is **reducing GPU cost**
(render scale, post-processing, single-pass stereo), and finally **reducing CPU
cost** (FEX TSO, per-frame mod overhead).

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

### 2.1 The game is hard-capped at 45 FPS by its own setting **[verified]**
`Graphics/FrameRate = 45` in `options.bin`. Subnautica applies this to
`Application.targetFrameRate`, which caps the render loop. In VR this means the
game submits at most 45 frames/sec to SteamVR, which then has to reproject
(motion-smooth) the other 45 of the 90 Hz. **This is almost certainly the
"45 fps" you're seeing** — it's not the hardware ceiling, it's a software cap.

### 2.2 The GPU is genuinely loaded (SteamVR already downscaled) **[verified]**
SteamVR's auto-resolution dropped to 64% because the Adreno 750 + Turnip stack
can't sustain full-res 90 Hz. So even uncapped, the GPU is a real constraint.

### 2.3 The CPU is paying a heavy translation tax **[hypothesis, high confidence]**
Every game-logic/CPU instruction runs through FEX's x86→ARM JIT. FEX defaults
to **TSO (Total Store Order)** memory-ordering emulation for compatibility,
which is significantly slower than native ARM memory ordering. The game is
Mono-based (managed code), so a large fraction of the frame is CPU-bound and
goes through the JIT. This is a per-frame tax on top of the GPU cost.

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

### 3.1 Remove the 45 FPS cap — **[mod], biggest & safest win**
Patch the game so that when VR is active, `Application.targetFrameRate` is set
to the HMD refresh rate (90) or `-1` (unlimited) instead of the 45 from
`Graphics/FrameRate`.

- **Where**: a new Harmony patch in this mod (e.g. on `GameSettings` /
  `VROptions` / the frame-rate setter, or simply a `LateUpdate`/`Update` that
  forces `Application.targetFrameRate` while `XRSettings.enabled`).
- **Expected gain**: if the GPU can actually do more than 45, this directly
  raises render FPS. Even if it can't, it removes the artificial ceiling and
  lets SteamVR's reprojection work from a higher base.
- **Risk**: low. Worst case the game renders at whatever the GPU can do.
- **Caveat**: verify the game doesn't re-apply the cap every frame (it may
  re-apply on settings load / `SerializeVRSettings`). The mod already patches
  `GameSettings.SerializeVRSettings`, so we can hook there too.

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

### 3.4 Try single-pass instanced stereo — **[mod], biggest GPU win, risky**
Patch `XRSettings.stereoRenderingMode = SinglePassInstanced` at VR init.

- **Expected gain**: potentially ~1.5–2× GPU throughput on the scene pass.
- **Risk**: **high**. Subnautica's custom shaders (water, terrain, UI) may not
  support instancing and can render incorrectly or break. This needs a
  test-on-device pass and probably a config flag to opt in/out.
- **Recommendation**: implement behind a config flag, default off, and test.

### 3.5 Reduce FEX CPU tax — **[config]**
FEX supports `STEAM_FEX_TSOENABLED` and `STEAM_FEX_MULTIBLOCK` (see
`FEX-Emu/fex-compat-tool`). TSO emulation is the big CPU cost.

- Try Steam launch options:
  ```
  STEAM_FEX_TSOENABLED=0 STEAM_FEX_MULTIBLOCK=1 WINEDLLOVERRIDES="winhttp=n,b" %command%
  ```
- **Expected gain**: potentially large CPU-side speedup (game logic, physics,
  Mono GC). **Risk**: TSO off can cause rare crashes/glitches in some games —
  test carefully. Multiblock is generally safe and helps JIT throughput.
- This is a device setting, not a mod change, but worth documenting here.

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
low-risk, low-gain cleanup.

### 3.7 Shader-cache warm-up — **[config]**
Mesa shader cache is only ~19 MB and no DXVK cache was found, so the game is
likely still compiling shaders on first encounters (stutter). Options:
- Play through the game once to warm caches (they persist).
- Consider a `dxvk.conf` with `dxvk.numCompilerThreads` tuning (DXVK 2.x
  compiles async by default; the main lever is just letting the cache build).
- **Expected gain**: removes stutter, not average FPS.

---

## 4. Recommended next steps (in order)

1. **Remove the 45 FPS cap in the mod** (3.1) — do this first; it's the
   cheapest and most likely to directly raise the number you're seeing.
2. **Measure** with the cap removed before changing anything else — use
   SteamVR's performance HUD / `mangoapp` to see whether we're now GPU-bound
   or CPU-bound.
3. If **GPU-bound**: apply 3.2 (lower render scale) and 3.3 (disable SSR/AO/
   DOF), then optionally try 3.4 (single-pass) behind a flag.
4. If **CPU-bound**: apply 3.5 (FEX TSO off / multiblock) and 3.6 (mod hot-path
   cleanup).
5. Warm shader caches (3.7) regardless.

## 5. What I can implement in this repo

- **3.1** — a Harmony patch forcing `Application.targetFrameRate` to 90 (or
  unlimited) while VR is active, plus a config entry.
- **3.2** — expose `VR/RenderScale` in `VREnhancements.cfg`.
- **3.3** — a "VR Performance" config toggle that disables SSR/AO/DOF/Bloom.
- **3.4** — a config-gated single-pass-instanced patch (default off).
- **3.6** — a hot-path cleanup pass (cache components, reduce per-frame work).

Items 3.5 and 3.7 are device/Steam settings — I can document exact commands,
but they're not code changes to this repo.
