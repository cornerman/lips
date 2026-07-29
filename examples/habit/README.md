<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `habit` language

This language crystallizes a single "habit tracker" home-manager program:
a small CLI tool that is compiled from source and dropped on the user's
PATH via `home.packages`.

Line shapes recognized:
- Two narrative sentences ("track daily habits from the terminal.", "each
  log line holds an ISO date and a habit name separated by a tab.") are
  pure decoration/structure: they describe the file format the built
  script implements, but name no option, so they crystallize as `concept`
  and need no rule. The tab-separated format they describe is baked
  directly into the shipped script as fixed structure.
- "the habit log is stored in <path>." states the log file location -- a
  program fact. It flows into the built script through a fill
  (`@logpath@`), so editing the path in the program and re-realizing
  changes the compiled tool without a fresh mint.
- "print a heatmap of the last <days> days for the habit named on the
  command line." states how many days the heatmap covers -- another fact,
  also carried into the script via a fill (`@days@`). "for the habit named
  on the command line" is read literally: the mechanism chosen is that the
  habit name always comes from argv, never from config, so that phrase is
  a fixed literal, not a hole.
- "install the tool as the command <name>." names the command the human
  wants on their PATH. That name is a program value, so it is captured and
  used everywhere the *installed binary's own name* matters: the
  derivation's pname and the destination filename in installPhase
  (`$out/bin/<name>`). It is NOT used to build a second, separately-named
  artifact key; since a home-manager program mints exactly one build here,
  the internal artifact bookkeeping key is `<self>` (the program's own
  file name), while the human's word governs the actually installed
  command name -- so renaming the command in the program still renames
  what lands on $PATH.

Mechanism choices:
- Builder: `stdenv.mkDerivation`, the plainest builder for "copy a script
  into $out/bin", with `dontBuild = true` and a custom `installPhase`
  (no compilation needed, so buildGoModule/buildRustPackage would be
  overkill).
- Package delivery: `home.packages = [ ${artifact.<self>} ]` -- the tool
  is a manually-invoked terminal command, not a background service, so no
  systemd unit is minted.
- `version = "0.1.0"` is an unobserved build constant (nixpkgs needs
  pname+version to name the derivation), chosen once at full confidence,
  never asked of the human.
- The script itself (source/run.sh) implements the stated algorithm:
  reads the tab-separated log, builds a set of dates the given habit was
  logged, and prints one glyph per day for the last N days.

Demands added so any program in this language states what the build
needs: the log path, the heatmap span, and the installed command name --
all three are also pinned with expects into their artifact slots
(fill.logpath, fill.days, args.pname).
