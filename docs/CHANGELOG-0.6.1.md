# Changes from v0.6.0 to v0.6.1

## New Features

- **Daily checks for new releases** — the CLI automatically checks GitHub once a day for newer releases and suggests running `upgrade` if one is available. This behaviour can be disabled with the `AutoUpdate` system config key.

## Improvements

- **Per-workspace platform selection** — during `init`, the CLI now prompts for which platforms to target, and platforms can be changed later with the `config platforms=...` command. Leaving platforms empty means all supported platforms will be used.
