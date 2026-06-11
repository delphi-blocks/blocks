# TODO

- [x] Verify the order in which dependencies are installed
- [x] Update the local repository if outdated
- [x] Delphi environment variable BLOCKSDIR
- [x] Add per package constraints (such as required Delphi version, ...)
- [x] `build` command that recompiles an already installed package
- [ ] Import and export of the dependency database so the same environment can be recreated on another machine
- [ ] Support for platforms other than Win32 and Win64
- [ ] Ability to pass a custom DEFINE during installation or in the manifest
- [ ] Dependency check during uninstall
- [ ] Install "packageless" library (FastMM4, DUnitX, ...)
- [ ] Handle naming conflicts (install folder, package names, DCU folder names)
- [ ] New repository location (private repo? HTTP url? Authentication?)
- [ ] New manifest scripts, such as a `copy`, `cmd`, `rename`, `fetch` ... (see [Scripts](#scripts))
- [ ] GUI version
- [ ] Expert version to be installed in the IDE

## Scripts

Example configuration:

```json
{
  "description": "Copy README.md",
  "command": "copy",
  "event": "afterCompile",
  "args": "*.README %DCU_PATH%"
}
```

* `command`: required
* `description`: optional, shown during the install process
* `event`: required
* `args`: optional (but may be required for some commands)

Available commands:

* `copyres`: copies resources and dfm files *(already implemented)*
* `copy source target`: copies the given files (supports wildcards)
* `move source target`: moves the given files (supports wildcards)
* `echo [arg1 [arg2 [...]]]`: prints the arguments *(already implemented)*
* `cmd [arg1 [arg2 [...]]]`: runs the given commands
* `bat filename`: runs the given batch file
