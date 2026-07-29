<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `habit` language

This language crystallizes a small habit-tracking CLI program description into a home-manager configuration.

**Line shapes recognized**

- `track daily habits from the terminal.` — a decorative intro heading; carries no value, so it becomes a `concept` with no rule.
- `the habit log is stored in <path>.` — states the filesystem path of the habit's TSV log. Captured as fact `habit.logpath`.
- `each log line holds an ISO date and a habit name separated by a tab.` — describes the log's file *format*. This is structure that goes straight into the source code of the built tool, not a value that flows through any option, so it is a `concept`.
- `print a heatmap of the last <days> days for the habit named on the command line.` — states how many days the heatmap should cover. Captured as fact `habit.heatmapdays`. ("the habit named on the command line" is interface structure — argv[1] — not a value, so it is folded into the same line's mechanism rather than captured separately.)
- `write the tool in go, using only the standard library with no external dependencies.` — a mechanism-selecting sentence: "go" and "no external dependencies" are literal tokens that pick the builder (`buildGoModule`, `vendorHash = null`) used elsewhere; the sentence itself carries no independent value, so it is a `concept`.
- `install the tool as the command <name>.` — names the installed command. This is the one place the program actually names the artifact, so it is captured as `habit.command.<name>` and that capture keys the artifact and the package list entry.

**Mechanism choices**

- The tool is built from source as `artifact.<name>` via `buildGoModule`, with `vendorHash = null` because the program explicitly states there are no external dependencies (stdlib only). `pname`/`version` are build constants (`version = "0.1.0"` is an arbitrary, effect-free placeholder).
- Rather than freezing the log path or the heatmap window into the compiled source (which would silently go stale on edits), both values are carried through two small `xdg.configFile` entries (`habit-logpath`, `habit-heatmapdays`) that the program reads at runtime under `$XDG_CONFIG_HOME`. This keeps every stated program value re-derivable from the config after edits.
- The built binary is added to `home.packages` via `${artifact.<name>}` so it lands on PATH as the named command.

**Invented, effect-free details**

- The two runtime config file names (`habit-logpath`, `habit-heatmapdays`) and the config-reading convention are ours to choose (mechanism), since the program never names its own config protocol.
- `version = "0.1.0"` is a build constant with no observable effect.

No gaps were hit; every stated program value (log path, heatmap window, command name) reaches a home-manager option, and the go/no-dependencies wording is honored by literal builder selection.
