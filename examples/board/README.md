<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `board` language

This language describes a small terminal kanban-board tool and how it is wired into the user's home-manager profile.

**Patterns**
- `show a kanban board in the terminal.` and `write the tool in go, using only the standard library with no external dependencies.` are decorative headings: they name the kind of program (a terminal kanban board) and the mechanism (Go, stdlib only, no external deps). Neither carries a value the config must hold, so both crystallize as `concept`s and need no rule. The "go / stdlib only" sentence is exactly what licenses the mechanism choice below (buildGoModule with `vendorHash = null`), so it is not a gap, it is read directly as a mechanism-selecting sentence.
- `the board is stored in <path>.` states the markdown file location -> `fact board.path`.
- `the board has the columns "<columns>".` states the column list as one quoted string (kept as one comma-joined value; the Go program itself splits it) -> `fact board.columns`.
- `install the tool as the command <name>.` names the installed command. Since the program itself names the binary, the artifact is keyed by that captured name (`tool.<name>`), not by the instance/file name, so renaming the command in the program renames the build.

**Rules / mechanism**
- `board.path` and `board.columns` are carried at runtime as environment variables (`home.sessionVariables.BOARD_PATH` / `BOARD_COLUMNS`) rather than baked into the source blob, so editing either line still takes effect without regenerating the tool. The Go program reads both with `os.Getenv` at startup.
- `tool.<name>` builds a Go program with `buildGoModule` (chosen because the program explicitly says "in go"). Since the program also says the tool uses only the standard library with no external dependencies, `vendorHash` is set to `null` (a legitimate buildGoModule mode for a module with nothing to vendor) -- a build-recipe constant, not a value the program need ever state. `version` is likewise a constant (`0.1.0`); nixpkgs needs pname+version together to name the derivation, and the program never speaks to versioning. The built package is added to `home.packages` so its `bin/<name>` (here `board`) lands on the user's PATH -- literally "installed as the command".
- The staged Go source (`go.mod`, `main.go`) implements the structural part of the program: it reads the two env vars, opens the markdown file, treats `## <column>`-style headings (case-insensitively matched against the configured column names) as section markers, collects the `- item` / `* item` bullets under each, and prints the columns side by side as a simple terminal table. No value from the program is frozen into this source; only the file-format/parsing structure lives there.

**Expects** pin that the stated board path and column list actually reach the session environment (`home.sessionVariables.BOARD_PATH`/`BOARD_COLUMNS`). No expect is written for the artifact/package wiring, since a package or build reference is not a checkable value.

**Nothing was demanded**: this one program already states every fact the language needs (path, columns, command name); the only invented pieces are pure build constants (builder choice, version, vendorHash), which are mechanism, not missing facts.
