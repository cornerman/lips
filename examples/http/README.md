<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `http` language

This language describes a small HTTP endpoint that answers a handful of
fixed paths with fixed text.

**The lines it accepts**

- `serve http on port 8080.` — the TCP port. It sets
  `services.nginx.defaultHTTPListenPort`, turns nginx on, and opens the port
  in the firewall.
- `run it as a systemd service named hello.` — the server's name. The name
  keys everything below it: the nginx virtual host is called `hello`, and the
  serving unit gets the systemd alias `hello.service`, so `systemctl status
  hello` works on the booted machine.
- `routes:` — a heading. It carries no value and realizes nothing.
- `- /health answers with the text "ok"` — one route. The path may be any
  path, the text is quoted so it may contain spaces. Each route becomes an
  nginx `location` under the named virtual host that answers `200` with that
  text as `text/plain`.

Route lines are read as items of the block opened by the `run it as a
systemd service named …` line, which is how each route knows which server it
belongs to. That means the naming line must come before the routes; the
`routes:` heading itself is free-standing decoration, so you may drop or
reword it only by regenerating.

**The mechanism I chose**

nginx, rather than a hand-written server binary. Every fact the programs
state — a port, a path, a body — is exactly an nginx virtual host, location
and `return`, so nothing had to be invented or compiled, and a later edit of
a route body flows straight through to the configuration. A route's body is
rendered as `default_type text/plain; return 200 '<body>';` inside the
location's `extraConfig` (this schema types `locations.*.return` as an
integer, so the body cannot ride there). Because the bodies are wrapped in
nginx single quotes, a body containing a single quote is not supported today.

**What I had to decide myself**

- The serving unit is nginx's own; the program's name is attached to it as a
  systemd *alias* (`hello.service`) rather than as a second unit, since a
  dummy unit next to nginx would serve nothing. No expect pins the alias,
  because the option holds the name with `.service` appended rather than the
  program's word verbatim; the word is pinned instead by the virtual-host key
  in the route expect.
- Content type `text/plain` for every route: the programs say "the text", so
  plain text is what they mean. If a route ever needs another type, that is a
  new word in the sentence and a regeneration.
- No claim is minted: this language is pure configuration, and the expects
  pin the port and every route body to the option that carries it.
