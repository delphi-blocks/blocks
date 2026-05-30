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
    "args": ["Compiled %PACKAGE% for %PLATFORM%/%CONFIG% into %DCU_PATH%"]
  }
]
```

| Field         | Required | Meaning                                                            |
|---------------|----------|--------------------------------------------------------------------|
| `command`     | yes      | Name of the built-in command to run (see [Commands](#commands)).   |
| `event`       | yes      | Lifecycle event the script is bound to (see [Events](#events)).    |
| `description` | no       | Free-text label, for humans.                                       |
| `args`        | no       | List of string arguments passed to the command.                    |

Scripts run **in declaration order** for a given event. A script whose `event`
does not match any fired event never runs.

## Variable expansion

Before a command runs, every `%VAR%` placeholder in its `command` and in each
`args` entry is replaced with the value of the corresponding event variable.
**Unknown variables expand to an empty string.**

The set of available variables depends on the event:

### Compile events (`beforeCompile`, `afterCompile`)

These fire **once per package**, for each platform and build config, so the
output paths point at the exact location that compilation used.

| Variable           | Value                                                                 |
|--------------------|-----------------------------------------------------------------------|
| `%PACKAGE%`        | Name of the package (`.dproj`) being compiled.                        |
| `%PLATFORM%`       | Target platform, e.g. `Win32`, `Win64`.                               |
| `%CONFIG%`         | Build config, `Debug` or `Release`.                                   |
| `%WORKSPACE_PATH%` | Workspace root directory.                                             |
| `%PROJECT_PATH%`   | Extracted project directory (`<workspace>\<package name>`).           |
| `%BPL_PATH%`       | BPL output dir (`<workspace>\.blocks\<platform>\bpl[\debug]`).        |
| `%DCP_PATH%`       | DCP output dir (`<workspace>\.blocks\<platform>\dcp[\debug]`).        |
| `%DCU_PATH%`       | DCU output dir (`<project>\lib\<platform>[\debug]`). See note below.  |

> **Note** — `%DCU_PATH%` is only set when the manifest's
> `packageOptions.keepProjectDcuPaths` is `false` (the default). When it is
> `true`, the DCU output is driven by each package's own `.dproj` and there is
> no single project-level DCU path, so `%DCU_PATH%` is empty.

### Install / uninstall events (`beforeInstall`, `afterInstall`, `beforeUninstall`, `afterUninstall`)

These fire **once per manifest**. Only workspace- and project-level paths are
meaningful at this stage:

| Variable           | Value                                          |
|--------------------|------------------------------------------------|
| `%WORKSPACE_PATH%` | Workspace root directory.                      |
| `%PROJECT_PATH%`   | Extracted project directory.                   |

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
  configs, so a script may run several times with different `%CONFIG%` /
  `%PLATFORM%` / output paths.
- Because `Install` resolves dependencies recursively, every manifest in the
  dependency tree fires its own install/uninstall events.
- Install/uninstall events only fire when the operation actually proceeds (for
  example, they do not fire when a package is already installed and up to date).

## Commands

A command may optionally be **bound to a set of events**. When bound, using it
under any other event raises an error. Using an unknown command name also raises
an error.

### `echo`

Prints its arguments (after variable expansion), joined by a single space, to
the console. Valid for any event.

```json
{ "event": "afterInstall", "command": "echo", "args": ["Installed into %PROJECT_PATH%"] }
```

### `copyres`

Copies resource files next to the compiled units. **Bound to `afterCompile`**
(it needs `%DCU_PATH%`).

What it does:

1. Reads the current `%PLATFORM%` and looks up that platform's `sourcePath`
   entries in the manifest:

   ```json
   "platforms": {
     "Win32": { "sourcePath": ["Source"] },
     "Win64": { "sourcePath": ["Source"] }
   }
   ```

2. Resolves each `sourcePath` against `%PROJECT_PATH%` (when relative).
3. Recursively copies every `.res` and `.dfm` found there into `%DCU_PATH%`,
   overwriting existing files.

It takes no `args`. Because `afterCompile` fires once per package, `copyres`
runs once per package and simply overwrites the same files — this is harmless
and intentionally produces no extra output. If `%DCU_PATH%` is empty (i.e.
`keepProjectDcuPaths` is enabled) the command raises an error.

```json
{ "description": "Copy resources and dfm", "event": "afterCompile", "command": "copyres" }
```

## Adding a new command

Commands live in `Source/Blocks.Service.Script.pas`. To add one:

1. Derive a class from `TScriptCommand` and override `Run`:

   ```pascal
   TMyCommand = class(TScriptCommand)
   public
     procedure Run(AManifest: TManifest; AArgs, AEnvironmentVariables: TStrings); override;
   end;
   ```

   - `AArgs` are the script args, already `%VAR%`-expanded.
   - `AEnvironmentVariables` holds the event variables (read extra ones directly,
     e.g. `AEnvironmentVariables.Values['DCU_PATH']`).
   - `AManifest` is the owning manifest, for commands that inspect it.

2. Register it in the unit's `initialization` section. Pass a list of events to
   restrict where it can be used; omit it to allow any event:

   ```pascal
   // valid for any event
   TScriptCommand.RegisterCommand('mycmd', TMyCommand);

   // restricted to afterCompile
   TScriptCommand.RegisterCommand('copyres', TCopyResCommand, [TScriptRunner.EventAfterCompile]);
   ```

Validation (unknown command, wrong event) and `%VAR%` expansion are handled
centrally by `TScriptRunner`, so commands only implement their own logic.
