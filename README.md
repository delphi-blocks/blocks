# DelphiBlocks

> **Early preview — work in progress.**

A command-line package manager for Delphi / RAD Studio. DelphiBlocks automates downloading, compiling, and registering third-party Delphi packages sourced from a GitHub-hosted registry.

## How it works

1. Reads a JSON manifest from the [blocks-repository](https://github.com/lminuti/blocks-repository).
2. Downloads the package source as a ZIP from GitHub.
3. Compiles it with MSBuild against the selected Delphi version.
4. Registers the library paths in the Delphi registry and records the installation in a local database (`.blocks/`).

## Requirements

- Windows
- Delphi / RAD Studio XE6 or later (BDS 14.0 – 37.0)
- MSBuild (bundled with RAD Studio)

## Usage

```
blocks <command> [options]

Commands:
  install <id[@constraint]>   Download, compile and register a package
  uninstall <id>              Remove a package from the workspace and database
  init                        Initialise the workspace and download the repository
  list                        List installed packages
  listproducts                List detected Delphi installations
  config [<key>[=<value>]]    Read or write workspace configuration
  view <id[@version]>         Show package details from the repository
  help [command]              Show help
```

### Quick start

```bat
REM Initialise the workspace in the current directory
blocks init

REM Install a package (prompts for Delphi version)
blocks install owner.package

REM Install a specific version
blocks install owner.package@1.2.0

REM Target a specific Delphi version, skip prompts
blocks install owner.package /product delphi13 /silent

REM Uninstall
blocks uninstall owner.package /product delphi13

REM List installed packages
blocks list
blocks list /product delphi12

REM View package info
blocks view owner.package@1.2.0
blocks view owner.package /versions

REM Manage repository sources
blocks config sources
blocks config /add sources=https://github.com/owner/my-repo
```

### Version constraints

Append `@<constraint>` to a package ID to pin or restrict the version:

| Syntax | Meaning |
|--------|---------|
| `@1.2.0` | Exact version |
| `@^1.2.0` | Same major (`>=1.2.0 <2.0.0`) |
| `@~1.2.0` | Same minor (`>=1.2.0 <1.3.0`) |
| `@>=1.0.0` | At least 1.0.0 |
| `@>=1.0.0 <2.0.0` | Explicit range |

> **Note:** In `cmd.exe` the `^` character must be escaped as `^^` (e.g. `owner.package@^^1.2.0`). In PowerShell no escaping is needed.

## Building from source

All source files are under `Source/`. Open a command prompt there and run:

```bat
REM Debug Win32 (default)
DelphiBlocks.Build.130.bat

REM Release Win32
DelphiBlocks.Build.130.bat Make Release Win32
```

Requires Delphi 13 Florence (`BDS=C:\Program Files (x86)\Embarcadero\Studio\37.0`).  
The compiled executable (`Blocks.exe`) is placed in the project root.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
