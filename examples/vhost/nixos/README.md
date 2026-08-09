<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `vhost` language

This language describes an nginx reverse-proxy / static-file gateway as a
list of virtual hosts and their locations.

Line shapes:
- `serve these sites over http with nginx.` -- a fixed opening sentence
  that turns nginx on (`services.nginx.enable = true`). It carries no
  program value, only the choice of mechanism (nginx, over plain http, no
  TLS), so it always realizes the same thing.
- `host <domain>:` -- opens a block for one virtual host, named by the
  domain that follows. It is a heading (`concept`): it introduces the
  location lines below it but sets nothing by itself beyond grouping them
  under that domain.
- `- <path> proxies to <url>.` (nested under a `host:` line) -- adds a
  location at `<path>` on that host that reverse-proxies to `<url>`. Maps
  to `services.nginx.virtualHosts.<domain>.locations.<path>.proxyPass`.
- `- <path> serves files from <dir>.` (nested under a `host:` line) -- adds
  a location at `<path>` on that host that serves static files from
  `<dir>` on disk. Maps to
  `services.nginx.virtualHosts.<domain>.locations.<path>.root`.

Mechanism choices: nginx is the only web server this language knows (the
opening sentence names it explicitly, so it is a literal, not a hole); no
TLS/ACME is configured since the program only ever asks for plain http.
Each `host:` block is keyed by the domain name, and each location line
within it is keyed by its path, giving two independent NixOS attrsOf
levels (`virtualHosts.<domain>` and `locations.<path>`) chained together --
this is how several hosts, and several paths per host, can be described
without collision, and how a later edit to one path's target or one
host's set of routes flows straight through to the realized config.

No demand was needed: every value this gateway setup requires (which
domains, which paths, proxy target or static directory) is always stated
directly on the line that introduces it, so there was nothing a program in
this language could leave silent.
