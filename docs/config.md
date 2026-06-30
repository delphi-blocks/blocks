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
| `toolarchitecture` | `default` \| `x32` \| `x64` | `default` | Architecture of the compiler tools MSBuild uses to build packages (Delphi 13+). |
| `cbuilderoutput` | string | *(empty)* | Value passed verbatim to MSBuild as `DCC_CBuilderOutput` when building packages (e.g. `All` to generate C++ output). |
| `idearchitecture` | `default` \| `Win32` \| `Win64` | `default` | Which IDE binary [`run`](cli.md#run) launches (Delphi 13+ ships a 64-bit IDE). |
| `idepersonality` | `default` \| `Delphi` \| `CBuilder` | `default` | IDE personality [`run`](cli.md#run) selects (`bds.exe -p`). |
| `idehighdpi` | `default` \| `unaware` \| `systemaware` \| `permonitor` \| `permonitorv2` \| `unawaregdiscaling` | `default` | HighDPI awareness override [`run`](cli.md#run) applies (`bds.exe -highdpi:`). |

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

### `toolarchitecture`

Selects which build of the Delphi command-line compiler MSBuild runs when Blocks
compiles a package. It maps directly to the MSBuild
`DCC_PreferredToolArchitecture` property:

- `default` (the default) leaves the choice to Delphi: the
  `/p:DCC_PreferredToolArchitecture` property is **not passed to MSBuild at all**,
  so the IDE/project's own behaviour applies.
- `x32` uses the 32-bit compiler tools (`bin\DCC32` / `bin\DCC64`).
- `x64` uses the 64-bit compiler tools (`bin64\DCC32` / `bin64\DCC64`), which
  give the compiler a larger memory space — useful for large packages that
  exhaust the 32-bit compiler's memory.

This option only changes which *tools* run; it does **not** change the produced
binary, so the output of a package is identical either way. It is only available
from **Delphi 13 (BDS 37.0)** onwards and applies to the Delphi Windows 32-bit
and 64-bit target compilers; older versions simply ignore the property.

`init` sets it to the default (`default`). Change it with `config`:

```
blocks config toolarchitecture=x64
```

### `cbuilderoutput`

Sets the value Blocks passes to MSBuild as the `DCC_CBuilderOutput` property when
it compiles a package. The string is used **verbatim**, so you can set any value
the Delphi compiler accepts — for example `All` to make the compiler emit the
C++ output (`.hpp` headers, `.obj`/`.lib`, package `.bpi`) alongside the Delphi
output, which is what C++Builder needs to consume the package.

When **empty** (the default) the `/p:DCC_CBuilderOutput` property is **not passed
to MSBuild at all**, so the project's own setting applies.

For the list of supported values and what each one produces, see the Embarcadero
documentation:
[Output - C/C++](https://docwiki.embarcadero.com/RADStudio/Athens/en/Output_-_C/C%2B%2B).

```
blocks config cbuilderoutput=All
blocks config cbuilderoutput=          # clear it (property not passed)
```

### `idearchitecture`, `idepersonality` and `idehighdpi`

These three keys configure how the [`run`](cli.md#run) command opens the Delphi
IDE for this workspace. They do not affect installing or compiling packages.

- `idearchitecture` — which IDE binary to launch. `default` and `Win32` open the
  32-bit IDE (the `App` registry value, `…\bin\bds.exe`); `Win64` opens the
  64-bit IDE (the `App64` value, `…\bin64\bds.exe`) when the installed Delphi
  provides one, otherwise it falls back to the 32-bit IDE. Delphi started
  shipping a 64-bit IDE with Delphi 13.
- `idepersonality` — the IDE personality passed as `bds.exe -p <personality>`.
  `default` passes nothing (the IDE picks its own default); `Delphi` and
  `CBuilder` force that personality.
- `idehighdpi` — the HighDPI awareness override passed as
  `bds.exe -highdpi:<value>`. `default` passes nothing (the IDE uses its
  configured setting); any other value forces that DPI awareness mode.

```
blocks config idearchitecture=Win64
blocks config idepersonality=Delphi
blocks config idehighdpi=permonitorv2
```

Each of these can also be supplied directly on the `run` command line as a
`key=value` argument, which overrides the stored value **for that launch only**
(see [`run`](cli.md#run)).

## System configuration

System configuration is stored in the Windows registry under `Software\Blocks`
and is shared by every workspace on the machine. Target it with the `/system`
option.

| Key           | Type    | Meaning                                                                                                   |
|---------------|---------|-----------------------------------------------------------------------------------------------------------|
| `InstallPath` | string  | Directory containing the `blocks.exe` to launch when multiple installations are present.                  |
| `AutoUpdate`  | boolean | Whether blocks checks GitHub once a day for a newer release. Defaults to `true` when unset.                |
| `GitPath`     | string  | Full path to `git.exe`, used to fetch `git` repositories. When unset, git is taken from the PATH.          |
| `SvnPath`     | string  | Full path to `svn.exe`, used to fetch `svn` repositories. When unset, svn is taken from the PATH.          |

### `InstallPath`

Selects which `blocks.exe` the launcher runs when more than one installation is
present. This key only exists when Blocks was installed through the setup
package and requires the launcher to function.

```
blocks config /system InstallPath
blocks config /system InstallPath=C:\Tools\Blocks
```

### `AutoUpdate`

Controls the automatic update check. When enabled (the default), any command
that opens the workspace checks GitHub at most once a day for a newer release
and, if one is found, suggests running `blocks upgrade`. Set it to `false` to
disable the check entirely; the value is read as `true` whenever it is absent
from the registry.

```
blocks config /system AutoUpdate
blocks config /system AutoUpdate=false
```

### `GitPath`

Full path to the `git.exe` used to fetch [`git`](manifest.md#repository) repositories.
When unset (the default), Blocks runs `git` from the system PATH; set this key only
when git is not on the PATH or you want to pin a specific install. Setting it checks
that the file exists.

```
blocks config /system GitPath
blocks config /system GitPath=C:\Program Files\Git\bin\git.exe
```

### `SvnPath`

Full path to the `svn.exe` used to fetch [`svn`](manifest.md#repository) repositories.
When unset (the default), Blocks runs `svn` from the system PATH; set this key only
when svn is not on the PATH or you want to pin a specific install. Setting it checks
that the file exists.

```
blocks config /system SvnPath
blocks config /system SvnPath=C:\Program Files\TortoiseSVN\bin\svn.exe
```
