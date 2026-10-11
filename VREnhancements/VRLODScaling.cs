using BepInEx.Configuration;
using HarmonyLib;
using UnityEngine;
using UnityEngine.XR;

namespace VREnhancements
{
    /// <summary>
    /// Aggressive VR-specific LOD / shadow scaling.
    ///
    /// The game is GPU-bound in VR (see doc/performance.md 2.2): it renders a
    /// lot of geometry that is invisible or irrelevant in VR (kelp, distant
    /// terrain, shadow cascades).
    ///
    /// IMPORTANT: Subnautica does NOT use Unity's QualitySettings.lodBias for
    /// its LOD system.  It uses a custom BehaviourLOD component with hardcoded
    /// distance thresholds (veryCloseThreshold/closeThreshold/farThreshold,
    /// default 10/50/500 m).  So we patch BehaviourLOD.Awake to scale those
    /// thresholds down while VR is active, which forces objects to drop to
    /// lower LOD states sooner (less geometry rendered).
    ///
    /// We also scale QualitySettings.shadowDistance/shadowCascades, which the
    /// game DOES read for shadow rendering.
    /// </summary>
    class VRLODScaling
    {
        public static ConfigEntry<bool> enabled;
        public static ConfigEntry<float> lodDistanceScale;
        public static ConfigEntry<float> shadowDistance;
        public static ConfigEntry<int> shadowCascades;

        // Saved originals so we can restore them when VR is not active.
        static float originalShadowDistance = 100f;
        static int originalShadowCascades = 2;
        static bool originalsSaved = false;
        static bool logged = false;

        public static void LoadConfig()
        {
            enabled = MainPatcher.VRConfig.Bind("Performance", "vrLODScaling", false,
                "Reduce LOD distances and shadow quality while VR is active to cut GPU load. Disable if LOD pop-in is too noticeable. Default off: tested 2026-10-11, no FPS gain (GPU is fill-rate/post-processing bound, not geometry bound).");
            lodDistanceScale = MainPatcher.VRConfig.Bind("Performance", "vrLODDistanceScale", 0.6f,
                "Multiplier applied to the game's LOD distance thresholds while VR is active. Lower = objects drop to lower detail sooner (more pop-in, less GPU load). 1.0 = default.");
            shadowDistance = MainPatcher.VRConfig.Bind("Performance", "vrShadowDistance", 60f,
                "Shadow distance in meters while VR is active. Lower = fewer shadowed pixels (less GPU load).");
            shadowCascades = MainPatcher.VRConfig.Bind("Performance", "vrShadowCascades", 2,
                "Shadow cascade count while VR is active. Lower = cheaper shadows (2 = two cascades, 4 = four).");
        }

        /// <summary>
        /// Applies the VR LOD/shadow overrides.  Called from a LateUpdate hook
        /// and after quality settings are (re)loaded.
        /// </summary>
        public static void Apply()
        {
            // Config entries are bound lazily (see LoadConfig); skip until ready.
            if (enabled == null || lodDistanceScale == null || shadowDistance == null || shadowCascades == null)
                return;

            if (!XRSettings.isDeviceActive)
                return;

            if (!originalsSaved)
            {
                originalShadowDistance = QualitySettings.shadowDistance;
                originalShadowCascades = QualitySettings.shadowCascades;
                originalsSaved = true;
            }

            if (enabled.Value)
            {
                if (Mathf.Abs(QualitySettings.shadowDistance - shadowDistance.Value) > 0.001f)
                    QualitySettings.shadowDistance = shadowDistance.Value;
                if (QualitySettings.shadowCascades != shadowCascades.Value)
                    QualitySettings.shadowCascades = shadowCascades.Value;

                if (!logged)
                {
                    logged = true;
                    Debug.Log($"[VR Enhancements] VR LOD scaling applied: lodDistanceScale={lodDistanceScale.Value}, shadowDistance={QualitySettings.shadowDistance}, shadowCascades={QualitySettings.shadowCascades}");
                }
            }
            else if (originalsSaved)
            {
                // Restore originals when disabled.
                QualitySettings.shadowDistance = originalShadowDistance;
                QualitySettings.shadowCascades = originalShadowCascades;
            }
        }

        /// <summary>
        /// Scales BehaviourLOD's distance thresholds down while VR is active.
        /// BehaviourLOD.Awake computes the squared thresholds from the linear
        /// ones, so we scale the linear ones before they are squared.
        /// </summary>
        [HarmonyPatch(typeof(BehaviourLOD), nameof(BehaviourLOD.Awake))]
        class BehaviourLOD_Awake_Patch
        {
            static void Prefix(BehaviourLOD __instance)
            {
                if (enabled == null || !enabled.Value)
                    return;

                if (!XRSettings.isDeviceActive)
                    return;

                float scale = lodDistanceScale.Value;
                if (scale <= 0f || scale >= 1f)
                    return;

                __instance.veryCloseThreshold *= scale;
                __instance.closeThreshold *= scale;
                __instance.farThreshold *= scale;
            }
        }

        /// <summary>
        /// Re-apply the overrides after the game (re)loads quality settings,
        /// since GraphicsPreset.Apply resets shadowDistance/etc.
        /// </summary>
        [HarmonyPatch(typeof(GraphicsUtil), nameof(GraphicsUtil.SetQualityLevel))]
        class SetQualityLevel_Patch
        {
            static void Postfix()
            {
                Apply();
            }
        }
    }
}
