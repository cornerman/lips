TARGET WORLD: NixOS (a whole machine, root). Emit NixOS option paths:
services.*, systemd.services.* and systemd.timers.*, environment.*,
networking.*, users.*, and so on. <self> keys an attrsOf-submodule
instance name (services.restic.backups.<self>, systemd.services.<self>).
