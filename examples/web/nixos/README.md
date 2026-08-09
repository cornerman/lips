<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `web` language

This language describes a tiny fixed-response HTTP server: a port to
listen on, a name for the service, and a list of routes, each with a
status code and a body.

Line shapes:
- `serve http on port <port>.` states the listening port. "http" is a
  fixed mechanism word (this language only ever builds plain HTTP
  servers); the port is the value.
- `run it as a systemd service named <name>.` names the service. Rather
  than inventing a custom binary, this engine realizes the whole program
  as an nginx virtual host (no source code to write, no per-route
  repetition to fake), so there is no literal systemd unit called
  `<name>` -- nginx itself is one shared system service. The name is
  instead written into the virtual host's `serverName`, which is the
  closest honest place for the human's chosen name to land and be
  checked.
- `routes:` is a heading with no value of its own -- a concept, decorative.
- `- <path> returns status <status> with body "<body>".` declares one
  route. Each bulleted route becomes its own nginx `location` block (keyed
  by its path, an attrsOf option, so any number of routes compose without
  collision), with `extraConfig` set to a literal `return <status>
  '<body>';` directive. This is data, not code, so adding a route is just
  adding a bulleted line -- nothing about the engine's shape changes, and
  no per-route source file is ever generated.

Mechanism choices made once for every program of this kind, not read from
any single program: the virtual host is marked `default = true` (there is
no notion of a domain name in this language, so it catches all requests
on its port), it listens on `0.0.0.0`, and the chosen port is also opened
in the firewall so the server is reachable. All of these are constants
this language always applies, never values a program states.

Every program must say what port to listen on and what to call the
service; a program silent about either is asked, since there is no sane
default for a port or a name. Every declared route contributes one
`location` block; there is no lower bound on how many routes a program
may declare (zero is a legal, if useless, web server).

Limitation worth knowing: a route's body is combined with its status
code into one nginx directive via positional token substitution, so it
works cleanly for single-word bodies ("hello", "gone", "ok"). A body with
embedded spaces would only have its first word land correctly -- the
grammar has no way to carry the "rest of the line" through a value
already built from two captured fields into one option's text.
