<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `http` language

This language describes one tiny http responder per program: a port, the text
it answers with, the name of the systemd service that runs it, and one worked
example of a request.

## The four line shapes

- `serve http on port 8080.` -- the TCP port. Any number; the port is also
  opened in the firewall (`networking.firewall.allowedTCPPorts`), which is what
  type-checks it as an integer.
- `respond to every request with the text "hello from lips".` -- the body
  returned for every path. Must be quoted; the quotes are dropped.
- `run it as a systemd service named hello.` -- the unit name. This word keys
  the unit itself (`systemd.services.hello`), and is repeated as the unit's
  `SyslogIdentifier` so it is visible in the journal (and pinnable by a test).
- `a request to / answers with the text "hello from lips".` -- an EXAMPLE, not
  configuration. It becomes a claim: the built binary is run in the build
  sandbox with `-check /` and its printed body must equal the stated text,
  byte for byte. This is the only thing that holds the baked source to the
  program's sentences, so a program is required to state one such line.

All four lines are required; a program missing one is refused with the question
printed beside it (see the demands).

## Mechanism, and why

No prebuilt server fit. nginx and caddy come with unit names of their own, and
the program insists on naming the service, so I write the server: a ~50-line Go
program (`buildGoModule`, no dependencies, `vendorHash = null`) that answers
every path with one fixed text.

The port and the text reach that binary as compile-time FILLS (`@port@`,
`@body@` in `main.go`), not as environment variables on the unit. That is
forced, not preferred: a rule can only key an option by its own captured words,
and the unit's name comes from a different line than the port does, so no rule
can write `systemd.services.<the-name>.environment.PORT`. Filed as gap
`cross-line-instance-key`. The practical consequence for you: editing the port
or the text rebuilds the little binary, and the values are pinned by expects on
the fills rather than on a module option.

The unit runs with `DynamicUser = true` plus `CAP_NET_BIND_SERVICE` (so ports
below 1024 work too), `Restart = always`, after `network.target`, wanted by
`multi-user.target`.

## The example, and where it runs

The claim runs the built binary itself with `-check <path>`: the binary starts a
listener on a kernel-chosen loopback port inside the sandbox, requests the given
path from itself, and prints the response body. That needs no booted machine and
no knowledge of the configured port -- which the claim rule could not see anyway,
for the same reason as above. It does mean the claim observes the handler and
the baked text, not the TCP port; the port is checked by type and by the two
options it lands in.

## Limits worth knowing

- Exactly one example line per program (gap `per-item-claim-key`).
- The response text is baked into a Go string literal, so a text containing a
  double quote or a backslash will not build. Plain prose is fine.
- Two programs of this language may run side by side: each gets its own unit
  name and its own build.

## Known Gaps

### cross-line-instance-key

blocked lines (three lines that together configure ONE unit):
  serve http on port 8080.
  respond to every request with the text "hello from lips".
  run it as a systemd service named hello.
A rule sees only its own decision, so the port rule cannot write into
systemd.services.<name>.environment.PORT -- <name> is bound by the service-name
line, a different decision. The only shared key available to every rule is
<self> (the file name), which the program's own word "hello" would then not
govern. Repro: two facts (server.port, service.<name>) whose values must land
in one attrsOf slot keyed by the second fact's value. Missing capability: a way
for one line's captured key to key another line's emit (a program-wide key, or
a block that can open on a non-heading line).

### per-item-claim-key

blocked line (a hypothetical second example in the same program):
  a request to /health answers with the text "ok".
Both example lines emit claim.serve.*, and two rules writing one option slot is
a conflict, so a program may state exactly one example. A claim id cannot be
keyed by <n:index> (the example lines sit under no heading) and keying it by
the path would put "/" in an identifier segment. Missing capability: an
index-like key for claims outside a block.

