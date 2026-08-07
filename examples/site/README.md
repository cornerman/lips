<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `site` language

This language describes one static website per program, served by nginx.

## Lines it accepts

- `serve the static files in <dir> at <host>.` — the only required line. It
  states two things at once: the directory on the machine that holds the
  files, and the hostname the site answers to. The directory becomes the
  virtual host's `root`, the hostname its `serverName`. Both are written as
  plain strings, never Nix paths, so the directory is read on the running
  machine rather than copied into the store.
- `enable HTTPS with a Let's Encrypt certificate.` — optional switch. When
  present, the virtual host gets `enableACME = true` and `forceSSL = true`
  (plain HTTP is redirected). Leave the line out and the site stays HTTP.
- `the Let's Encrypt account email is <email>.` — the ACME account address.
  It sets `security.acme.defaults.email` and, with it,
  `security.acme.acceptTerms = true`: a program that names an account email
  for Let's Encrypt is taken to accept their terms, since no certificate can
  be issued otherwise. That acceptance is the one thing here not literally
  said by a program; nothing else is invented.
- `extra routes:` — a heading. It realizes nothing on its own; it only opens
  the block that the route lines below it belong to.
- `<path> => <status> with text <body>` — one route, under that heading. The
  path keys an nginx `location`, and the status and body are served directly
  by nginx as `default_type text/plain; return <status> '<body>';`. The body
  may be several words; it is served as plain text, which is what "with text"
  was read to mean. Two routes never collide because each keys its own
  location by its own path.

## Mechanism, and one deviation worth knowing

Everything lands in `services.nginx`, which the first line also enables. The
virtual host is keyed by the program's own instance name (`blog.site.lips` →
`services.nginx.virtualHosts.blog`) and the hostname from the program is put
in `serverName`, which nginx uses for `server_name` and which ACME uses to
name the certificate. Keying the attribute set by the hostname itself would
have been the more direct shape, but a hostname contains dots and a subject
segment in this engine cannot carry them, so the hostname would stop being an
editable value. Keying by the instance name keeps the hostname a hole, lets
two site programs compose in one configuration, and produces the same nginx
behaviour.

## What a program must state

The directory, the hostname and the account email are demanded: a program
missing any of them is sent back with the question above rather than given a
guessed default. HTTPS and the routes block are optional. Every value a
program states is pinned by an expect on the exact option it must reach.
