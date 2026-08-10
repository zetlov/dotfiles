# Windows audio dependencies

`AudioOutputInstaller.psm1` owns installation of the shared Windows audio
dependency used by both the GlazeWM and Komorebi configurations.

The consumers pin `AudioDeviceCmdlets` to version `3.1.0.2`. The installer
downloads that exact package from a fixed PowerShell Gallery HTTPS package URI;
it does not use PowerShellGet, PackageManagement, repository configuration, or
module discovery through `PSModulePath`.

Only the package-root `AudioDeviceCmdlets.psd1` and `AudioDeviceCmdlets.dll`
entries are extracted. Their reviewed SHA-256 hashes are checked before and
after installation. Package and archive-entry size limits reject unexpected
artifacts before extraction. The fixed destination is the Windows PowerShell current-user
module directory under
`MyDocuments\WindowsPowerShell\Modules\AudioDeviceCmdlets\3.1.0.2`, even when
the installer is called from PowerShell 7. Existing complete installations are
accepted only when both files match; partial, modified, or reparse-point-backed
installations fail closed and are never replaced automatically.

The Windows known-folder result for `MyDocuments` is the trust root so that
supported redirected Documents folders continue to work. Every existing path
component below that root, through the version directory and the two module
files, is rejected when it is a reparse point.

The reviewed SHA-256 values are:

- `AudioDeviceCmdlets.psd1`:
  `0D657B8DDE3DC9B090716162ED351B68F785F50483B92E937528D082469DBFB5`
- `AudioDeviceCmdlets.dll`:
  `2E81666DD09BC835C669DAF9771686FDAD5651FBEBB600A234F11AF80CA5D25F`

The runtime switching script repeats the path, reparse-point, and hash checks,
imports the exact manifest with `-Force -PassThru`, verifies the resulting module
base and version, and invokes command objects captured from that module's
`ExportedCommands`. This prevents an earlier same-name module on `PSModulePath`
or an unqualified command from changing which code runs.

The checked-in hashes authenticate the reviewed module files after download,
but HTTPS and the pinned Gallery URI still provide package transport and
availability. Updating the module version therefore requires reviewing the new
package contents and updating the URI, destination version, and both hashes
together.

Audio switching scripts, device matching configuration, hotkeys, and runtime
deployment paths remain owned by their window-manager directories.
