# Configuration

Blocks keeps two independent sets of configuration values:

- **Workspace configuration** — settings that belong to a single workspace
  (the directory you ran `blocks init` in). Stored as JSON in
  `.blocks/workspace.json`.
- **System configuration** — machine-wide settings stored in the Windows
  registry under `Software\Blocks`.

Both are read and written with the [`config`](cli.md#config) command. With no
arguments it prints the current values; pass `<key>` to read a single value and
`<key>=<value>` to set one. Use `/system` to target the system configuration
instead of the workspace.

```
blocks config                              # show all workspace values
blocks config product                      # read one workspace value
blocks config registrykey=myprofile        # set one workspace value
blocks config /system                      # show all system values
blocks config /system InstallPath=C:\Tools\Blocks
```

## Workspace configuration

These values live in `.blocks/workspace.json` and apply only to the current
workspace.

| Key                   | Type    | Default | Meaning                                                                                  |
|-----------------------|---------|---------|------------------------------------------------------------------------------------------|
| `sources`             | list    | the official `blocks-repository` | Comma-separated list of repository URLs `init` downloads the package index from. |
| `platforms`           | list    | *(empty = all)* | Platforms this workspace targets when installing/uninstalling packages.         |
| `product`             | string  | *(set by `init`)* | Target Delphi version name (e.g. `delphi12`, `delphi13`).                       |
| `registrykey`         | string  | `BDS`   | Registry profile key for the target Delphi IDE, matching `bds.exe -r <key>`.            |
| `updatedcpsearchpath` | boolean | `false` | Whether `init` adds the Blocks DCP output directory to the Delphi library Search Path.  |

### `sources`

The list of repositories `init` reads the package manifests from. Use `/add`
and `/delete` to edit the list without rewriting it whole:

```
blocks config /add sources=https://github.com/owner/my-repo
blocks config /delete sources=https://github.com/owner/my-repo
```

A source does not have to be a GitHub URL. Any entry that does **not** start
with `http` is treated as a **local folder** path; the folder must contain a
`.blocks\repository` subdirectory (the same layout produced by a downloaded
repository). Both relative and absolute paths are accepted, which is handy for
testing a repository you are developing or for keeping a private,
third-party index alongside the official one:

```
..\my-repository
C:\path\to\local-repository
```

For example, to add a local folder:

```
blocks config /add sources=C:\path\to\local-repository
```

After changing `sources`, run `blocks init` to refresh the local repository
index.

### `platforms`

The platforms this workspace builds and registers packages for. When **empty**
(the default), a package is installed for every platform it supports that is also
active and buildable in the configured Delphi version — the original behaviour.
When the list is **not empty**, install, build and uninstall skip any platform
that is not in it.

`init` offers to set this interactively (after choosing the Delphi version), or
you can pass it non-interactively with `init /platforms Win32,Win64`. Edit it
later with `config`, using `/add` and `/delete` for single platforms:

```
blocks config platforms=Win32,Win64
blocks config /add platforms=Win64
blocks config /delete platforms=Win64
blocks config platforms=                 # clear the list (target all platforms again)
```

Platform names are validated against — and stored in the canonical casing of —
the buildable platforms of the configured Delphi version, so an unknown or
non-installed platform is rejected.

### `product` and `registrykey`

`product` selects which installed Delphi version Blocks compiles and registers
packages for; `registrykey` selects the IDE registry profile (the same key you
would pass to `bds.exe -r <key>`). Both are normally set once by `blocks init`
and rarely changed afterwards.

### `updatedcpsearchpath`

When `true`, `init` adds the workspace's DCP output directory
(`<workspace>\.blocks\<platform>\dcp`) to the Delphi library **Search Path** in
the registry, for every supported platform.

**Normally leave this at `false`.** It changes a global IDE setting, not just
the current project, so Blocks does not touch it unless you opt in.

You may want to enable it in one specific situation: when you compile a package
**outside** of Blocks — for example one of your own packages, or any package
that is not part of the Blocks ecosystem — and that package depends on a package
that *was* installed by Blocks. In that case the compiler cannot find the
dependency's compiled output, because its directory is not on the IDE Search
Path, and compilation fails. Setting `updatedcpsearchpath=true` adds that output
directory to the Search Path, so the dependency is found and the external
package compiles.

After changing this key, run `blocks init` to apply it.

```
blocks config updatedcpsearchpath=true
blocks init
```

> **Note:** registering the workspace's `.blocks` directory as the `$(BLOCKSDIR)`
> environment variable always happens during `init`; it is not controlled by
> this flag.

## System configuration

System configuration is stored in the Windows registry under `Software\Blocks`
and is shared by every workspace on the machine. Target it with the `/system`
option.

| Key           | Type   | Meaning                                                                                                   |
|---------------|--------|-----------------------------------------------------------------------------------------------------------|
| `InstallPath` | string | Directory containing the `blocks.exe` to launch when multiple installations are present.                  |

### `InstallPath`

Selects which `blocks.exe` the launcher runs when more than one installation is
present. This key only exists when Blocks was installed through the setup
package and requires the launcher to function.

```
blocks config /system InstallPath
blocks config /system InstallPath=C:\Tools\Blocks
```
