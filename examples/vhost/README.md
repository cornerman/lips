<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `vhost` language

This language describes an nginx reverse-proxy/static-file gateway: one or
more virtual hosts, each with a list of locations that either proxy to a
backend URL or serve static files from a directory.

Line shapes:
- `serve these sites over http with nginx.` -- a fixed opening sentence,
  present once per program, that turns nginx on (`services.nginx.enable`).
  Both "http" and "nginx" are mechanism choices this language always makes
  the same way (no TLS/other-server support was shown), so they stay literal
  words rather than holes.
- `host <domain>:` -- opens a block naming one virtual host. It carries no
  option of its own (nginx creates the vhost implicitly from its locations),
  so it is a `concept`, but the domain it captures is threaded into every
  location line nested under it.
- `- <path> proxies to <url>` (nested under a host) -- a reverse-proxy
  location: requests to `<path>` on that host are forwarded to `<url>`.
  Realized as `proxyPass` on that host+path's location, with
  `recommendedProxySettings` turned on as a fixed best-practice companion
  (not a program value, so not a hole).
- `- <path> serves files from <dir>` (nested under a host) -- a static
  location: requests to `<path>` are served from the directory `<dir>`,
  realized as that location's `root`.

Each host's domain and each location's path are captures, not literals, so
adding a new host or route is just adding a new line -- the engine fans
each one out to its own `services.nginx.virtualHosts.<domain>.locations.<path>`
slot without collision, however many hosts or routes a program lists.
Every proxied URL and every served directory is pinned by an expect against
the option it must reach; the `nginx.enable` boolean is a fixed constant,
not a program value, so it carries no expect.
