using BepInEx.Configuration;
using HarmonyLib;
using UnityEngine;
using UnityEngine.XR;

namespace VREnhancements
{
    /// <summary>
    /// Removes the game's artificial FPS cap while VR is active.
    ///
    /// Subnautica applies Graphics/FrameRate (default 45) to
    /// Application.targetFrameRate, which caps the render loop.  In VR this
    /// means the game submits at most 45 frames/sec to SteamVR, which then has
    /// to reproject the other 45 of the 90 Hz.  This patch forces
    /// Application.targetFrameRate to the HMD refresh rate (or unlimited) while
    /// XRSettings is active, so the game can render at whatever the GPU can
    /// actually sustain.
    ///
    /// The game re-applies the cap whenever settings are (re)loaded, so we also
    /// hook GameSettings.SerializeVRSettings (which the mod already patches in
    /// AdditionalVROptions) to re-apply our override after the game does.
    /// </summary>
    class FrameRateFix
    {
        public static ConfigEntry<int> targetFPS;
        public static ConfigEntry<bool> enabled;

        public static void LoadConfig()
        {
            enabled = MainPatcher.VRConfig.Bind("Performance", "removeFPSCap", true,
                "Remove the game's FPS cap while VR is active so the game can render at the HMD refresh rate instead of the 45 FPS default.");
            targetFPS = MainPatcher.VRConfig.Bind("Performance", "targetFPS", 0,
                "Target frame rate while VR is active. 0 = unlimited (-1), 90 = HMD refresh rate. Any other value is used as-is.");
        }

        /// <summary>
        /// Applies the frame rate override.  Called from a LateUpdate hook and
        /// after settings are (re)loaded.
        /// </summary>
        public static void Apply()
        {
            // Config entries are bound lazily (see LoadConfig); skip until ready.
            if (enabled == null || targetFPS == null)
                return;

            if (!enabled.Value)
                return;

            if (!XRSettings.isDeviceActive)
                return;

            int fps = targetFPS.Value;
            if (fps <= 0)
                fps = -1; // unlimited (0 in config = unlimited; 90 = HMD refresh rate, used as-is)

            if (Application.targetFrameRate != fps)
            {
                Application.targetFrameRate = fps;
                Debug.Log($"[VR Enhancements] Removed FPS cap: targetFrameRate = {fps}");
            }
        }

        /// <summary>
        /// Re-apply the override after the game (re)loads its settings, since
        /// the game writes Graphics/FrameRate back into Application.targetFrameRate.
        /// </summary>
        [HarmonyPatch(typeof(GameSettings), nameof(GameSettings.SerializeVRSettings))]
        class SerializeVRSettings_Patch
        {
            static void Postfix()
            {
                Apply();
            }
        }
    }
}
