# Manifest Scripts

Blocks can run small built-in **commands** at well-defined points of the
install/uninstall pipeline. They are declared in a package manifest under the
`scripts` array and are useful for tasks the compiler does not do on its own —
for example copying resource files next to the produced DCUs.

## Declaring scripts in the manifest

Add a `scripts` array to the manifest. Each entry binds a **command** to a
lifecycle **event**, with optional **args**:

```json
"scripts": [
  {
    "description": "Copy resources and dfm",
    "event": "afterCompile",
    "command": "copyres"
  },
  {
    "description": "Tell the user where the DCUs went",
    "event": "afterCompile",
    "command": "echo",
    "args": "Compiled $(PACKAGE) for $(PLATFORM)/$(CONFIG) into $(DCU_PATH)"
  }
]
```

| Field         | Required | Meaning                                                            |
|---------------|----------|--------------------------------------------------------------------|
| `command`     | yes      | Name of the built-in command to run (see [Commands](#commands)).   |
| `event`       | yes      | Lifecycle event the script is bound to (see [Events](#events)).    |
| `description` | no       | Free-text label, for humans.                                       |
| `filter`      | no       | Boolean expression deciding whether the script actually runs when its event fires. See [Filtering](#filtering). |
| `args`        | no       | Arguments for the command. **The shape is command-specific** — a string for `echo`, an object for `compile`/`expert`. See each command below. |

Scripts run **in declaration order** for a given event. A script whose `event`
does not match any fired event never runs.

## Variable expansion

Before a command uses an argument, every `$(VAR)` placeholder in it — and in the
script's `command` — is replaced with the value of the corresponding event
variable. **Unknown variables expand to an empty string.** Each command decides
which of its arguments are expanded (e.g. `echo` expands its message, `compile`
expands its `projectFile`).

The set of available variables depends on the event:

### Compile events (`beforeCompile`, `afterCompile`)

These fire **once per package**, for each platform and build config, so the
output paths point at the exact location that compilation used.

| Variable             | Value                                                                 |
|----------------------|-----------------------------------------------------------------------|
| `$(PACKAGE)`         | Name of the package being compiled, **without path and without the `.dproj` extension** — the `name` from the manifest's `packages` list, with `$(PACKAGE_VERSION)` already expanded (e.g. `JclVcl`, or `Trysil370` for a manifest declaring `Trysil$(PACKAGE_VERSION)`). |
| `$(PLATFORM)`        | Target platform, e.g. `Win32`, `Win64`.                               |
| `$(CONFIG)`          | Build config, `Debug` or `Release`.                                   |
| `$(WORKSPACE_PATH)`  | Workspace root directory.                                             |
| `$(PROJECT_PATH)`    | Extracted project directory (`<workspace>\<package name>`).           |
| `$(MANIFEST_PATH)`   | Directory of the manifest being installed (`<workspace>\.blocks\repository\<vendor>\<name>\<version>`). |
| `$(BPL_PATH)`        | BPL output dir (`<workspace>\.blocks\<platform>\bpl[\debug]`).        |
| `$(DCP_PATH)`        | DCP output dir (`<workspace>\.blocks\<platform>\dcp[\debug]`).        |
| `$(DCU_PATH)`        | DCU output dir (`<workspace>\.blocks\lib\<name>\<platform>[\debug]`). |

### Install / fetch / uninstall events (`beforeInstall`, `afterInstall`, `beforeFetchSources`, `afterFetchSources`, `beforeUninstall`, `afterUninstall`)

These fire **once per manifest**. Only workspace- and project-level paths are
meaningful at this stage:

| Variable              | Value                                                              |
|-----------------------|--------------------------------------------------------------------|
| `$(WORKSPACE_PATH)`        | Workspace root directory.                                     |
| `$(PROJECT_PATH)`          | Extracted project directory.                                  |
| `$(MANIFEST_PATH)`         | Directory of the manifest being installed (`<workspace>\.blocks\repository\<vendor>\<name>\<version>`). |
| `$(PACKAGE_VERSION)`       | Package-version suffix of the target IDE (e.g. `370` for Delphi 13). |
| `$(SHORT_PACKAGE_VERSION)` | Same suffix without its trailing zero (e.g. `37` for Delphi 13). |

On `beforeFetchSources` the project directory has been cleaned but the sources
are **not on disk yet**, so `$(PROJECT_PATH)` points at a directory that does not
exist (or is empty) at that moment.

## Filtering

An `event` alone is often too coarse: the compile events fire once per package,
**per platform and per config**, so a script bound to `afterCompile` runs many
times. The optional `filter` narrows that down to the runs you care about:

```json
{
  "description": "Only on the Win32 release build of JclVcl",
  "event": "afterCompile",
  "command": "copyres",
  "filter": "$(PLATFORM) = 'Win32' and $(CONFIG) = 'Release' and $(PACKAGE) = 'JclVcl'"
}
```

The expression is evaluated by the same Delphi expression evaluator that resolves
the MSBuild conditions of a `.dproj`, with these rules:

- Every `$(VAR)` is the event variable of that name — see the tables in
  [Variable expansion](#variable-expansion) for what each event exposes.
- **All values are strings**, so string literals go in single quotes:
  `$(PLATFORM) = 'Win32'`. Comparisons are **case-sensitive**, and the values
  Blocks produces have a fixed casing: `Win32` / `Win64` / `Linux64` …,
  `Debug` / `Release`.
- A variable **not available for that event** (or misspelled) evaluates to the
  empty string, exactly as it does in variable expansion — so
  `$(DCU_PATH) <> ''` is a way to ask "am I on a compile event?".
- Operators: `=`, `<>`, `<`, `>`, `and`, `or`, `not`, and parentheses.
- An **absent or empty** `filter` means "always run".
- An expression that is not valid raises an error and stops the install, so a
  typo in a filter is reported instead of silently disabling the script.

More examples:

```json
{ "event": "afterCompile", "command": "copyres", "filter": "$(CONFIG) = 'Release'" }
```

```json
{
  "event": "afterCompile",
  "command": "echo",
  "filter": "$(PLATFORM) = 'Win32' or $(PLATFORM) = 'Win64'",
  "args": "Built the Windows target $(PACKAGE)"
}
```

## Events

| Event             | Fires                                                                 | Granularity      |
|-------------------|-----------------------------------------------------------------------|------------------|
| `beforeCompile`   | Before each package is compiled.                                      | per package      |
| `afterCompile`    | After each package is compiled (before it is registered).            | per package      |
| `beforeInstall`   | After dependencies are resolved, before fetching/compiling sources.  | per manifest     |
| `afterInstall`    | After the package is registered and the local database is updated.   | per manifest     |
| `beforeFetchSources` | Before the package sources are fetched, after the project dir is cleaned. | per manifest |
| `afterFetchSources`  | After the package sources have been fetched into the project dir.   | per manifest     |
| `beforeUninstall` | Before unregistering packages, while the project files still exist.  | per manifest     |
| `afterUninstall`  | After the package has been removed from the database.                 | per manifest     |

Notes:

- Compile events run for every platform **and** for both `Debug` and `Release`
  configs, so a script may run several times with different `$(CONFIG)` /
  `$(PLATFORM)` / output paths.
- Because `Install` resolves dependencies recursively, every manifest in the
  dependency tree fires its own install/uninstall events.
- Install/uninstall events only fire when the operation actually proceeds (for
  example, they do not fire when a package is already installed and up to date).
- `beforeFetchSources` / `afterFetchSources` fire only when sources are actually
  fetched: they are skipped for meta-packages (repository type `none`) and for
  build-only installs (`build` command), which fetch nothing. They fire between
  `beforeInstall` and `afterInstall`.

## Commands

A command may optionally be **bound to a set of events**. When bound, using it
under any other event raises an error. Using an unknown command name also raises
an error.

### `echo`

Prints its message (after variable expansion) to the console. `args` is a single
string. Valid for any event.

```json
{ "event": "afterInstall", "command": "echo", "args": "Installed into $(PROJECT_PATH)" }
```

### `fetch`

Downloads a file from a URL to a local destination. Valid for any event.

`args` is an object:

| Field        | Required | Meaning                                                          |
|--------------|----------|------------------------------------------------------------------|
| `url`        | yes      | URL to download. Variable-expanded.                              |
| `outputFile` | yes      | Local file path to write to. **Variable-expanded**, so it can point at any event path (e.g. `$(PROJECT_PATH)`, `$(DCU_PATH)`). |

Both fields are mandatory; an empty value (including one that expands to empty)
raises an error. Missing output directories are created, and an existing output
file is overwritten. Redirects are followed.

```json
{
  "description": "Download a prebuilt resource",
  "event": "afterCompile",
  "command": "fetch",
  "args": {
    "url": "https://example.com/assets/data.bin",
    "outputFile": "$(DCU_PATH)\\data.bin"
  }
}
```

### `copy`

Copies a file or a whole directory from one path to another. Valid for any event.

`args` is an object:

| Field       | Required | Meaning                                                          |
|-------------|----------|------------------------------------------------------------------|
| `source`    | yes      | File or directory to copy. Variable-expanded; a relative path is resolved against `$(PROJECT_PATH)`. |
| `target`    | yes      | Destination file (when `source` is a file) or directory. Variable-expanded; a relative path is resolved against `$(PROJECT_PATH)`. |
| `recursive` | no       | When `source` is a directory, also copy its sub-directories. Defaults to `false`; ignored for a single-file copy. |

`source` and `target` are mandatory; an empty value (including one that expands
to empty) raises an error, as does a `source` that does not exist. Missing target
directories are created, and existing files are overwritten.

When `source` is a directory, its files are copied **into** `target` (the
directory itself is not recreated as a level); with `"recursive": true` the whole
tree below it is copied as well. When `source` is a file and `target` is an
existing directory, the file is copied into it keeping its name.

> The former field names `inputFile` and `outputFile` are deprecated but still
> accepted, so existing manifests keep working. They are only read when `source` /
> `target` are absent.

```json
{
  "description": "Copy a config file next to the DCUs",
  "event": "afterCompile",
  "command": "copy",
  "args": {
    "source": "Source\\settings.ini",
    "target": "$(DCU_PATH)\\settings.ini"
  }
}
```

```json
{
  "description": "Copy the include files, sub-directories included",
  "event": "afterFetchSources",
  "command": "copy",
  "args": {
    "source": "$(PROJECT_PATH)\\jcl\\source\\include",
    "target": "$(DCU_PATH)\\include",
    "recursive": true
  }
}
```

### `copyres`

Copies resource files next to the compiled units. **Bound to `afterCompile`**
(it needs `$(DCU_PATH)`).

What it does:

1. Reads the current `$(PLATFORM)` and looks up that platform's `sourcePath`
   entries in the manifest:

   ```json
   "platforms": {
     "Win32": { "sourcePath": ["Source"] },
     "Win64": { "sourcePath": ["Source"] }
   }
   ```

2. Resolves each `sourcePath` against `$(PROJECT_PATH)` (when relative).
3. Recursively copies every `.res` and `.dfm` found there into `$(DCU_PATH)`,
   overwriting existing files.

It takes no `args`. Because `afterCompile` fires once per package, `copyres`
runs once per package and simply overwrites the same files — this is harmless
and intentionally produces no extra output.

```json
{ "description": "Copy resources and dfm", "event": "afterCompile", "command": "copyres" }
```

### `compile`

Compiles an extra project that the normal package pipeline does not build.
**Bound to the install events** (`beforeInstall`, `afterInstall`).

`args` is an object:

| Field         | Required | Meaning                                                                    |
|---------------|----------|----------------------------------------------------------------------------|
| `projectFile` | yes      | Path to the `.dproj` to build, relative to `$(PROJECT_PATH)` (or absolute).  |
| `platforms`   | yes      | Array of platforms to build, e.g. `["Win32", "Win64"]`.                     |

The project is always built in the `Release` config. Every listed platform whose
compiler is actually installed is built; platforms without a compiler are skipped
(if none is available the command fails). Blocks injects the same output paths it
uses for packages — the `.blocks\<platform>\dcp` directory is prepended to the
unit search path, and `DCC_DcuOutput` / `DCC_ExeOutput` point at
`.blocks\lib\<manifest name>\<platform>[\debug]`, so the produced binary lands
next to its DCUs.

Because `projectFile` is variable-expanded first, `$(PACKAGE_VERSION)` can target a
`.dproj` whose name embeds the IDE package suffix:

```json
{
  "description": "Compile the Trysil helper",
  "event": "afterInstall",
  "command": "compile",
  "args": {
    "projectFile": "Trysil.Helper\\Trysil.Helper$(PACKAGE_VERSION).dproj",
    "platforms": ["Win32", "Win64"]
  }
}
```

### `expert`

Same `args` and build behaviour as [`compile`](#compile), plus an optional
`description` field. Each compiled platform's output is treated as a design-time
**IDE expert** `.dll` and registered so the IDE loads it on next start. Typical
use is building an expert that depends on the runtime package just installed.
**Bound to the install events.**

| Field         | Required | Meaning                                                          |
|---------------|----------|------------------------------------------------------------------|
| `projectFile` | yes      | As for [`compile`](#compile).                                    |
| `platforms`   | yes      | As for [`compile`](#compile).                                    |
| `description` | no       | Name to register the expert under (defaults to the `.dll` file name). |

After each successful platform build the produced `.dll` (named after the
`.dproj`, in the output dir described above) is registered: a value named after
the `description` (or the `.dll` file name when omitted) is written under
`HKCU\Software\Embarcadero\<regkey>\<bdsversion>\Experts` (Win32) or
`...\Experts x64` (Win64), with the full `.dll` path as its value.

On `uninstall` these registrations are removed automatically — no mirror script
is needed. Blocks scans both `Experts` keys and deletes every value whose path
points into this package's blocks lib folder
(`<workspace>\.blocks\lib\<manifest name>\...`, matched both as the absolute path
and as the `$(BLOCKSDIR)\lib\<manifest name>\...` macro form).

```json
{
  "description": "Compile and register the Trysil expert",
  "event": "afterInstall",
  "command": "expert",
  "args": {
    "projectFile": "Trysil.Expert\\Trysil.Expert$(PACKAGE_VERSION).dproj",
    "platforms": ["Win32", "Win64"],
    "description": "Trysil IDE Expert"
  }
}
```

