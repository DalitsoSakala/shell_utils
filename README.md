# Reusable Shell Utilities

Bash helpers you can source into your shell. Files meant for sourcing use the `*_ref.sh` suffix; run `init.sh` once to wire selected files into `~/.bashrc`.

## Setup

```bash
./init.sh
```

You will be prompted to choose which `*_ref.sh` files to include. Options:

- numbers — e.g. `1` or `1 2` / `1,2`
- `a` — include all
- `q` — cancel

Then open a new shell, or run `source ~/.bashrc`. Re-run `./init.sh` whenever you add a new `*_ref.sh` and want it loaded.

## Files

### `init.sh`

Installer (not sourced every session). Lists `*_ref.sh` files in this folder, lets you pick which ones to load, and writes a marked block at the end of `~/.bashrc` that sources those files. Safe to re-run; it replaces the previous block.

### `git_ref.sh`

Git helpers scoped to the current author (`git config user.email`). Provides:

#### `git-ls`

Lists unique file paths touched by your commits in a date range (defaults to today).

| Option | Description |
|--------|-------------|
| `-c`, `-commit` | Starting revision for `git log` (default: `HEAD`) |
| `-s`, `-since` | Inclusive start date `YYYY-MM-DD` (default: today) |
| `-e`, `-until` | Inclusive end date `YYYY-MM-DD` (default: today) |
| `-x`, `-exclude` | Pathspec to exclude |

Flags accept `-flag=value` or `-flag value`.

```bash
git-ls -since=2026-07-01 -until=2026-07-18 -exclude=vendor/
```

#### `git-dif`

Runs `git-ls` with the same options, then opens matching files in `git difftool` against the chosen commit (`-c` / `-commit`, default `HEAD`). Prints a message if nothing matches.

```bash
git-dif -since=2026-07-01 -c HEAD~3
```

## Adding helpers

Create a new file ending in `_ref.sh` in this folder, define functions in it, then run `./init.sh` and select it so it is sourced from `~/.bashrc`.
