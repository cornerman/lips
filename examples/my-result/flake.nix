# lips addressable entry. Generated; do not edit. Running is `nix` over this dir.
{
  description = "lips-compiled program (nixpkgs resolved ambiently)";
  inputs.nixpkgs.url = "flake:nixpkgs";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
      nixosBuilds = system:
        let
          evalNixos = extra: mods: import (nixpkgs + "/nixos/lib/eval-config.nix") {
            inherit system;
            modules = extra ++ mods;
          };
          evalConfig = extra: evalNixos extra [ ./default.nix ];
          shellStub = { system.stateVersion = "24.11"; };
          # A fixed hostname so the VM boot script has a fixed name to run.
          vm = (evalConfig [
            (nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")
            { system.stateVersion = "24.11"; networking.hostName = "lips";
              virtualisation.graphics = false; users.users.root.password = ""; }
          ]).config.system.build.vm;
          basePackages = (evalNixos [ shellStub ] []).config.environment.systemPackages;
          cfg = (evalConfig [ shellStub ]).config;
          shellPackages = nixpkgs.lib.subtractLists basePackages
            cfg.environment.systemPackages;
          shell = (pkgsFor system).mkShell { packages = shellPackages; };
          baseServices = builtins.attrNames (evalNixos [ shellStub ] []).config.systemd.services;
          serviceShells = nixpkgs.lib.listToAttrs (map (u: {
            name = "service-${u}";
            value = (pkgsFor system).mkShell {
              packages = shellPackages;
              env = cfg.systemd.services.${u}.environment;
            };
          }) (nixpkgs.lib.subtractLists baseServices (builtins.attrNames cfg.systemd.services)));
        in { inherit vm shell serviceShells; };
    in {
      nixosModules.default = import ./default.nix;
      packages = forSystems (system: {
        vm = (nixosBuilds system).vm;
      });
      apps = forSystems (system:
        let b = nixosBuilds system; in {
          vm = { type = "app"; program = "${b.vm}/bin/run-lips-vm"; };
        });
      devShells = forSystems (system:
        let b = nixosBuilds system; in {
          default = b.shell;
        } // b.serviceShells);
    };
}
