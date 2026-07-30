TARGET WORLD: home-manager (one user's $HOME, unprivileged). Emit
home-manager option paths ONLY, never NixOS system options: programs.*,
services.* (home-manager user services), systemd.user.services.* and
systemd.user.timers.*, home.packages, home.file.*, home.sessionVariables,
xdg.*. There is no system-level config and no root. <self> keys an
attrsOf-submodule instance name (systemd.user.services.<self>).
