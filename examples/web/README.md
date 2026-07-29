<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `web` language

This language describes a small Go HTTP server run as a systemd service, with its port, its unit name, and its route table all read from the program text.

**Line shapes recognized**

- `serve http on port <port>.` -- the port the server listens on. Read into the systemd unit's `PORT` environment variable, which the compiled server reads at startup.
- `run it as a systemd service named <name>.` -- names both the systemd unit's identity-bearing values (the built binary, the Go module, the derivation `pname`) via the capture `<name>`. The systemd *unit key* itself uses `<self>` (the program's file instance), since NixOS needs a fixed attrset key regardless of the program's wording, but every value the program actually names (`ExecStart`'s binary path, `pname`, the Go module name via a fill) is driven by `<name>`, so editing "named X" renames the binary end to end.
- `write the server in go, using only the standard library with no external dependencies.` -- this sentence *selects* the build mechanism (Go, `buildGoModule`, and `vendorHash = null` because there are no external dependencies to vendor). It carries no separate value of its own beyond that selection, so it is recorded as a decorative `concept` and the mechanism is baked into rule r2 directly.
- `routes:` -- a heading, `concept`, introducing the bulleted route list below it.
- `- <path> returns status <status> with body "<body>".` -- one HTTP route. Each bullet is its own instance, keyed by `<path>`, contributing a status fact and a body fact.

**Mechanism chosen for routes (and why)**

A naive design would bake each route into the Go source as its own `if` branch, but the number of routes varies with the program and a *fill* can only replace a single marker, never repeat a code block per route -- so that would not survive an edit that adds a fourth route. Instead the Go source is generic: at startup it scans `/etc/http-routes/<name>/{status,body}` for every subdirectory NixOS creates and registers a handler for each one it finds. The *data* (which routes exist, their status, their body) lives in `environment.etc` entries keyed by the route's own path (`environment.etc.http-routes<path>/status.text`, `.../body.text`), which is ordinary attrsOf aggregation across bullets; the *code* stays fixed and route-count-agnostic. This sidesteps the repeating-structure limitation entirely, so no gap was needed for the routes.

**Artifact**

`artifact.<name>` builds the Go program with `buildGoModule`, `pname`/`version` set (version is a fixed placeholder, a build constant with no observable effect), `vendorHash = null` (no external deps, per the program's own words), and a `fill.name` substituting `@name@` in `go.mod`'s `module` line so the compiled binary's name matches `<name>`, matching the `ExecStart` path `${artifact.<name>}/bin/<name>`.

**Assumptions / invented constants**

- The systemd unit is enabled via `wantedBy = [ "multi-user.target" ]`, standard practice for "run it as a systemd service", not stated explicitly but implied by the instruction.
- `version = "0.1.0"` is an arbitrary build placeholder, invisible to the program's behavior.
- The route-config directory `/etc/http-routes` is an internal wiring convention, not a program value.

**Demands**

If a program omits the port line or the "named ..." line, `q1`/`q2` ask for them, since both are load-bearing facts with no sensible default.
