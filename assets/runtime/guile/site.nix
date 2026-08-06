# How a clause site becomes a runnable program on this runtime.
#
# Written once and shared by every program, which is what makes it acceptable
# for a file of Nix to name Guile and a load path: it is not per-program source,
# it is this runtime's own adapter at build level. lips copies it and calls it,
# knowing only that it takes { pkgs, name, src } and returns a derivation.
{ pkgs, name, src }:
pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = [ pkgs.guile ];
  # guile-json is not in R7RS-small, so the load path is where this runtime's
  # JSON contract actually comes from.
  text = ''
    export GUILE_LOAD_PATH=${pkgs.guile-json}/share/guile/site/3.0''${GUILE_LOAD_PATH:+:$GUILE_LOAD_PATH}
    export GUILE_LOAD_COMPILED_PATH=${pkgs.guile-json}/lib/guile/3.0/site-ccache''${GUILE_LOAD_COMPILED_PATH:+:$GUILE_LOAD_COMPILED_PATH}
    exec guile --no-auto-compile -s ${src}/main.scm "$@"
  '';
}
