# TODO

- [x] Verify the order in which dependencies are installed
- [x] Update the local repository if outdated
- [x] Delphi environment variable BLOCKSDIR
- [x] Add per package constraints (such as required Delphi version, ...)
- [x] `build` command that recompiles an already installed package
- [x] Change macros from %NAME% to $(NAME)
- [x] Support for platforms other than Win32 and Win64
- [x] Set up the MSBuild environment by reading `rsvars.bat` (or `rsvars64.bat` on Win64/Delphi 13+) instead of hardcoded paths
- [x] Add an application icon to the executable
- [x] Config variable to use `DCC_PreferredToolArchitecture` (`x32` or `x64`) with *msbuild* 
- [x] Dependency check during uninstall
- [x] On `update`, recompile transitive dependents too (today only direct dependents are recompiled, so a dependent of a dependent can be left with stale DCUs)
- [x] Import and export of the dependency database so the same environment can be recreated on another machine (`export` command + `install <manifest-file>` of a meta-package)
- [ ] `update` without a version constraint should target the highest version within the same major that is also compatible with all other installed packages (not just the latest in-major release, but the best version satisfying the upward dependency graph)
- [ ] Support for private SVN e GIT repository (needs command line git.exe or svn.exe)
- [ ] Parallel builds for all the platforms supported to improve speed
- [ ] Test installation/uninstallation on macOS and mobile (Android, iOS): verify the `bpl<name>.so`/`.dylib` output naming and the `.imp.o` import-object location
- [ ] Ability to pass a custom DEFINE during installation or in the manifest
- [ ] Should the `build` command act recursively on dependencies?
- [ ] Install "packageless" library (FastMM4, DUnitX, ...)
- [ ] Handle naming conflicts (install folder, package names, DCU folder names)
- [ ] New repository location (private repo? HTTP url? Authentication?)
- [ ] New manifest scripts, such as a `copy`, `cmd`, `rename`, `fetch` ... (see [Scripts](#scripts))
- [ ] Graphical (GUI) front-end for the tool
- [ ] IDE expert that integrates Blocks directly into the Delphi IDE

## Scripts

Example configuration:

```json
{
  "description": "Copy README.md",
  "command": "copy",
  "event": "afterCompile",
  "args": ["*.README", "$(DCU_PATH)"]
}
```

* `command`: required
* `description`: optional, shown during the install process
* `event`: required
* `args`: optional (but may be required for some commands)

Available commands:

* `copyres`: copies resources and dfm files *(already implemented)*
* `echo [arg1 [arg2 [...]]]`: prints the arguments *(already implemented)*
* `compile expert\MyExpert$(BDSVERSION) [/p:win32,win64] [/c:release]`: compile a .dproj for the specified platform and config
* `regwrite`: ???
* `copy source target`: copies the given files (supports wildcards)
* `move source target`: moves the given files (supports wildcards)
* `cmd [arg1 [arg2 [...]]]`: runs the given commands
* `bat filename`: runs the given batch file
