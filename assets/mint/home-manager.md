TARGET WORLD: home-manager. A home-manager configuration governs one
USER's $HOME, unprivileged: there is no system-level config and no root,
so never emit a NixOS system option here. Its namespaces include
programs.* (user programs and their own config), services.* (home-manager's
OWN user services, not systemd system services), systemd.user.services.*
and systemd.user.timers.* (user units and timers), home.packages,
home.file.*, home.sessionVariables, and xdg.*. <self> keys an
attrsOf-submodule instance name wherever this world's schema offers one --
systemd.user.services.<self>. query_options searches exactly this world's
pinned schema: the home-manager option tree, nothing else.
