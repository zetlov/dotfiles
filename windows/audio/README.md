# Windows audio dependencies

`AudioOutputInstaller.psm1` owns installation of the shared Windows audio
dependency used by both the GlazeWM and Komorebi configurations.

The consumers pin `AudioDeviceCmdlets` to version `3.1.0.2` and install it for
the current user from PowerShell Gallery. The module bootstraps the NuGet
package provider when needed and verifies that the requested version is
available after installation.

Audio switching scripts, device matching configuration, hotkeys, and runtime
deployment paths remain owned by their window-manager directories.
