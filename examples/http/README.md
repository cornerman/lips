<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `http` language

This program describes a single self-written Go HTTP server, deployed as one systemd service.

Line shapes recognized:
- `serve http on port <port>.` — fixes the listen port. The value feeds a `PORT` environment
  variable on the service (read by the Go program at runtime) and is also opened in the host
  firewall, since a program stating it serves http on a port means that port should be reachable.
- `respond to every request with the text "<text>".` — fixes the response body. The value is
  compiled into the Go source through a `fill` (marker `@RESPONSE_TEXT@`), since it never changes
  at runtime.
- `write the server in go, using only the standard library with no external dependencies.` — this
  line is pure mechanism selection: "go" picks `buildGoModule` as the builder, and "standard
  library / no external dependencies" justifies `vendorHash = null` (no modules to vendor). It
  carries no per-program value, so its fact has an empty, fixed assertion and a rule that only
  sets build-recipe constants (builder, version placeholder, vendorHash, source path).
- `run it as a systemd service named <name>.` — the human-chosen name. Per the instance-naming
  rule, the systemd unit key itself is `<self>` (the program's own instance, not a name read from
  the program), but the captured word is not decoration: it becomes the artifact's `pname`, the
  `@NAME@` fill for `go.mod` (which is what actually determines the built binary's filename), and
  the literal binary name in `ExecStart`, so editing this word renames the built program.

Mechanism choices: `pkgs.buildGoModule` for a small dependency-free Go program (plainest builder
for "go, standard library only"); a `0.1.0` version placeholder (build constant, no observable
effect); `vendorHash = null` (no external deps, so no vendoring to hash); PORT delivered via an
environment variable (the idiomatic runtime-configurable knob for a Go net/http server) rather than
a compile-time fill, since a port is the kind of value that should stay adjustable without a
rebuild; the response text, by contrast, is static content and is compiled in via a fill.
`networking.firewall.allowedTCPPorts` is opened for the same port, since a program that serves an
http port is assumed to want it reachable.

No demands were needed: the four lines already state every fact the language requires (port, text,
language/mechanism, service name).
