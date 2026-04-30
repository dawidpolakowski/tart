# tart

`tart` is a lightweight command-line tool for logging task activity.

It keeps the daily workflow fast, while presenting a more predictable CLI surface:

* command-based interface
* backwards-compatible quick logging
* file-based storage
* human-readable weekly logs
* strict date and ISO week validation
* configurable log directory

## Screenshot

![tart screenshot](./src/Screenshot.png)

## Installation

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/dawidpolakowski/tart/main/scripts/install.sh | bash
```

The installer puts `tart` in:

```text
~/.local/bin/tart
```

If `~/.local/bin` is not already in your `PATH`, the installer prints the exact line to add to your shell profile.

Install from a local clone:

```bash
git clone https://github.com/dawidpolakowski/tart.git
cd tart
./scripts/install.sh
```

Choose another install directory:

```bash
TART_INSTALL_DIR="$HOME/bin" ./scripts/install.sh
```

### Windows

Install Git for Windows first, because `tart` runs through Git Bash on Windows.

Then run this in PowerShell:

```powershell
irm https://raw.githubusercontent.com/dawidpolakowski/tart/main/scripts/install.ps1 | iex
```

The installer puts `tart` in:

```text
%LOCALAPPDATA%\tart\bin
```

It also adds that directory to your user `PATH`. Open a new terminal after installation, then run:

```powershell
tart version
```

Install from a local clone:

```powershell
git clone https://github.com/dawidpolakowski/tart.git
cd tart
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

## Usage

Show the current week's log:

```bash
tart
tart list
```

Add a task entry:

```bash
tart add "implemented login feature"
```

Quick logging is still supported:

```bash
tart "implemented login feature"
```

Show today's entries:

```bash
tart today
tart --today
```

Show a specific week:

```bash
tart week 2026-04-30
tart list --week 2026-W18
```

Print the resolved log path:

```bash
tart path
tart path 2026-W18
```

Show configuration:

```bash
tart config
```

## Commands

```text
tart add <message...>             Add a task entry for today
tart list [--week <ref>]          Show entries for a week
tart today                        Show today's entries
tart week [<ref>]                 Show entries for the week containing <ref>
tart path [<ref>]                 Print the log file path for a week
tart init                         Create the log directory
tart config                       Show resolved configuration
tart version                      Show version
tart help                         Show help
```

Legacy aliases are still available:

```text
tart -t | --today
tart -tw | --this-week
tart --week <ref>
```

## Week References

Week commands accept either:

```text
YYYY-MM-DD
YYYY-Www
```

Date references can be any date in the target week. `tart` resolves them to the Monday log file for that ISO week.

Examples:

```bash
tart week 2026-04-30
tart week 2026-W18
```

Both resolve to:

```text
2026-04-27.log
```

## Configuration

Default log directory:

```bash
~/Documents/tart
```

Override it for your shell:

```bash
export TART_LOGDIR="$HOME/somewhere/tart"
```

Override it for one command:

```bash
tart --log-dir "$HOME/tmp/tart" add "tested release candidate"
```

## Data Format

Each week is stored in its own file, named after the Monday of that week:

```text
2026-04-27.log
```

Entries are plain text:

```text
YYYY-MM-DD <message>
```

Example:

```text
2026-04-27 implemented login feature
2026-04-28 fixed auth bug
2026-04-30 reviewed API changes
```

## Development

Run the test suite:

```bash
./tests/run.sh
```

The tests are dependency-free Bash smoke and regression tests. They use isolated temporary log directories and pin the current date with `TART_TODAY`.

## Philosophy

`tart` tracks what you did, not how long it took.

It is intentionally small, dependency-free, and easy to inspect, but the command surface is structured enough to feel reliable in day-to-day professional use.
