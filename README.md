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
DelphiBlocks.exe [options]

  -Init                    Initialise workspace (clone package registry)
  -Install <path|url|id>   Install a package by file path, URL, or registry ID
  -Uninstall               Remove the package from the workspace and database
  -Product <version>       Target Delphi version (e.g. delphi12, delphi13)
  -Commit <sha>            Pin installation to a specific GitHub commit
  -WorkspacePath <dir>     Override workspace root (default: current directory)
  -ProjectFolder <dir>     Override the extracted project directory name
  -BuildOnly               Compile without re-downloading
  -Overwrite               Overwrite an existing project directory
  -Silent                  Skip interactive prompts
  -List                    List packages installed in the workspace
  -ListProducts            List detected Delphi installations
  -Help                    Show usage
```

### Quick start

```bat
REM Initialise the workspace in the current directory
DelphiBlocks.exe -Init

REM Install a package (uses the detected Delphi version)
DelphiBlocks.exe -Install owner.packagename

REM Target a specific Delphi version
DelphiBlocks.exe -Install owner.packagename -Product delphi13
```

## Building from source

All source files are under `Source/`. Open a command prompt there and run:

```bat
REM Debug Win32 (default)
DelphiBlocks.Build.130.bat

REM Release Win32
DelphiBlocks.Build.130.bat Make Release Win32
```

Requires Delphi 13 Florence (`BDS=C:\Program Files (x86)\Embarcadero\Studio\37.0`).  
The compiled executables (`Blocks.exe`, `Launcher.exe`) are placed in the project root.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
