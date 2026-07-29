<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `postgres` language

This language describes a single PostgreSQL server provisioned by `services.postgresql`.

Three line shapes are recognized:

1. `run a postgresql database server.` — a fixed, hole-free sentence that
   selects the mechanism: it turns on `services.postgresql.enable`. Since
   the sentence carries no program value (only the literal words
   "postgresql" and "database server", which pick the module), it is
   realized at full confidence with a constant `true`.

2. `provision a database named <name>.` — captures a database name and
   contributes it to `services.postgresql.ensureDatabases`, a plain list of
   strings. Each such line is its own value-keyed fact (`db.<name>`), so
   several database lines aggregate into the same list via NixOS's normal
   list-option merge, exactly like a bulleted package list.

3. `provision a user named <user> who owns the <db> database.` — captures
   both the user name and the database it owns. Per the given direction,
   ownership in `services.postgresql.ensureUsers` is expressed only through
   `ensureDBOwnership = true`; nixpkgs then grants ownership of the
   database whose name equals the user's name, so no SQL or explicit
   grant is written. The line's assertion joins both captured words
   (`"<user> <db>"`) so the rule can address them individually as
   `<value.1>` (user) and `<value.2>` (db): `<value.1>` fills the `name`
   field of the `ensureUsers` entry, and `<value.2>` is also folded into
   `ensureDatabases`, guaranteeing the owned database is declared to exist
   (ownership of a database that was never ensured would be meaningless).
   This mirrors the plain database line's contribution to the very same
   list option, so the two rules concatenate cleanly.

Demands `db.<name>` and `user.<user>.owner` mean: any program written in
this language must state at least one database and, if it wants
ownership, name both the user and the database it owns; a program
missing these lines is asked to state them.

Nothing needed to be invented beyond the mechanism choice of
`services.postgresql` itself (directed explicitly) and the constant
`true` values for `enable` / `ensureDBOwnership`, both fixed by the
module's own contract rather than by the program.
