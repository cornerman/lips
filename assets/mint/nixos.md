TARGET WORLD: NixOS. A NixOS configuration governs a whole MACHINE,
evaluated as root, so every option you emit affects the system as a whole,
never one user's session alone. Its namespaces include services.* (system
services), systemd.services.* and systemd.timers.* (units and timers),
environment.* (system-wide packages and files), networking.*, and users.*.
<self> keys an attrsOf-submodule instance name wherever this world's schema
offers one -- systemd.services.<self>, or a service family's own instance
table (an option shaped like services.<name>.<instances>.<self>).
query_options searches exactly this world's pinned schema: the NixOS
option tree, nothing narrower and nothing wider.

A CLAIM MAY BE OBSERVED IN A BOOTED MACHINE here: this world has one, so a
command that reaches beyond the program's own artifacts (a systemctl call, a
curl against a running service) is run inside the booted module. It costs a
boot, so prefer an observable over the program's own binary where the
behaviour lives in a binary.
