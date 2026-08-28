# Windows audio output switching

The active Windows audio component installs a private `Ctrl+Alt+F12` shell
transport and the runtime files under:

```text
%LOCALAPPDATA%\dotfiles\audio
```

Kanata maps held `F13/F15+M` to that transport chord. The shortcut is stored in
the current user's Start Menu Programs folder, so Windows Explorer registers it
without another resident hotkey daemon. `Ctrl+Alt+F12` is an implementation
detail; the user-facing binding is held `F13/F15+M`. The Komorebi rollback
configuration does not register a competing audio binding.

`audio-output.local.json` can override the checked-in device patterns without
being tracked. During migration, the installer also accepts the existing
`windows/komorebi/audio-output.local.json` override.

The component pins `AudioDeviceCmdlets` to version `3.1.0.2`. The installer
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

Install or update only this component from WSL:

```bash
/init /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
  -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$PWD/windows/install.ps1")" \
  -Mode Install -Component audio
```

The default Windows component plan includes audio, WezTerm, and Kanata.
