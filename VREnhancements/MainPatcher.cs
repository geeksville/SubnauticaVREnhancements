using System;
using UnityEngine;
using UnityEngine.XR;
using BepInEx;
using HarmonyLib;
using BepInEx.Configuration;

namespace VREnhancements
{
    [BepInPlugin("com.whotnt.subnautica.vrenhancements.mod", "VREnhancements", "3.2.1")]
    //This entire class was created by ChatGPT based on the previous code to only patch whenever a VR headset is active!
    public class MainPatcher : BaseUnityPlugin
    {
        public static ConfigFile VRConfig = new ConfigFile(Paths.ConfigPath + "\\VREnhancements.cfg", true);
        private bool patched = false;

        private void Awake()
        {
            // Load mod config (frame rate override etc.) up front so the
            // LateUpdate hook has valid values even before the game's first
            // settings (de)serialization.
            AdditionalVROptions.LoadVRConfig();

            // Subscribe to VR device loaded event
            XRDevice.deviceLoaded += OnVRDeviceLoaded;

            // Optional: If VR is already active at startup, patch immediately
            if (XRSettings.isDeviceActive)
            {
                OnVRDeviceLoaded(XRSettings.loadedDeviceName);
            }
        }

        private void LateUpdate()
        {
            // Cheap per-frame check: re-apply the FPS override in case the game
            // (or a settings reload) reset Application.targetFrameRate.
            FrameRateFix.Apply();
        }

        private void OnVRDeviceLoaded(string loadedDeviceName)
        {
            if (patched) return; // Prevent double-patching

            try
            {
                Harmony harmony = new Harmony("com.whotnt.subnautica.vrenhancements.mod");
                harmony.PatchAll();
                patched = true;
                Console.WriteLine($"[VR Enhancements] Patched for device: {loadedDeviceName}");
            }
            catch (Exception ex)
            {
                Debug.Log("Error with VR Enhancements patching: " + ex.Message);
            }
        }
    }
}
