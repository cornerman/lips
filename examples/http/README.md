<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `http` language

## What this language describes

A program in this language is a tiny, always-on HTTP server, one systemd
service per program file. It reads exactly three sentences:

- `serve http on port <port>.` -- which port the server listens on.
- `respond to every request with the text "<text>".` -- the fixed text sent
  back to every request, on every path.
- `run it as a systemd service named <name>.` -- a human-readable name for
  the resulting systemd unit.

All three are required (each has a demand), since a server with no port, no
response text, or no stated name is not a fully specified program.

## Mechanism

Each program is realized as one systemd service, keyed by the program's own
instance name (its filename) via `<self>` -- this is what lets several
`*.http.lips` programs coexist in one machine configuration without their
units colliding.

The actual server is a small Go program (`buildGoModule`), built once as a
shared artifact named literally `http-echo` (not per-instance): its logic
never depends on which program is using it, only on the port and text each
program supplies, and those reach it at *runtime* through two environment
variables on the systemd unit, `PORT` and `RESPONSE_TEXT` -- not baked into
the binary at build time. This means the same compiled binary serves every
program written in this language; only the unit's environment differs.
`vendorHash` is `null` because the server uses only the Go standard library,
with no external modules to vendor.

The stated service name doesn't rename the systemd unit itself (that key is
always `<self>`, matching the file), but it does become the unit's
`description`, so it still governs something real and editing it changes
the realized module.

## What I had to invent

- The port and response text travel to the binary via environment
  variables rather than being compiled in, since that is the natural way
  for a value to reach a long-running server without rebuilding it, and it
  keeps the build itself independent of any one program's content.
- The artifact's package name (`http-echo`), version (`0.1.0`), and the
  choice of `buildGoModule` are fixed mechanism decisions -- the programs
  never name the underlying binary, so nothing here should be a hole.
- `wantedBy = [ "multi-user.target" ]` and `after = [ "network.target" ]`
  are the ordinary defaults for an always-on network service; the programs
  never discuss startup ordering, so these are mechanism constants, not
  holes.

No expects were written for the build/derivation options (`ExecStart`,
`artifact.http-echo.*`), since those hold package/build references, not
checkable program values; the three real values (port, text, name) each
have their own expect against the option they land in.
