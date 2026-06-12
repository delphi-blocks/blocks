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
| `$(PACKAGE)`         | Name of the package (`.dproj`) being compiled.                        |
| `$(PLATFORM)`        | Target platform, e.g. `Win32`, `Win64`.                               |
| `$(CONFIG)`          | Build config, `Debug` or `Release`.                                   |
| `$(WORKSPACE_PATH)`  | Workspace root directory.                                             |
| `$(PROJECT_PATH)`    | Extracted project directory (`<workspace>\<package name>`).           |
| `$(BPL_PATH)`        | BPL output dir (`<workspace>\.blocks\<platform>\bpl[\debug]`).        |
| `$(DCP_PATH)`        | DCP output dir (`<workspace>\.blocks\<platform>\dcp[\debug]`).        |
| `$(DCU_PATH)`        | DCU output dir (`<workspace>\.blocks\lib\<name>\<platform>[\debug]`). |

### Install / uninstall events (`beforeInstall`, `afterInstall`, `beforeUninstall`, `afterUninstall`)

These fire **once per manifest**. Only workspace- and project-level paths are
meaningful at this stage:

| Variable              | Value                                                              |
|-----------------------|--------------------------------------------------------------------|
| `$(WORKSPACE_PATH)`   | Workspace root directory.                                          |
| `$(PROJECT_PATH)`     | Extracted project directory.                                       |
| `$(PACKAGE_VERSION)`  | Package-version suffix of the target IDE (e.g. `370` for Delphi 13). |

## Events

| Event             | Fires                                                                 | Granularity      |
|-------------------|-----------------------------------------------------------------------|------------------|
| `beforeCompile`   | Before each package is compiled.                                      | per package      |
| `afterCompile`    | After each package is compiled (before it is registered).            | per package      |
| `beforeInstall`   | After dependencies are resolved, before fetching/compiling sources.  | per manifest     |
| `afterInstall`    | After the package is registered and the local database is updated.   | per manifest     |
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

