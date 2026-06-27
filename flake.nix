{
  description = "Phenix Neovim configuration";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    phenix-pins.url = "github:matthis-k/phenix-pins";
    nix-wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";
    nix-wrapper-modules.inputs.nixpkgs.follows = "phenix-pins/nixpkgs";
    nixpkgs.follows = "phenix-pins/nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      imports = [ ./modules/standalone.nix ];
      flake.flakeModules.default = import ./modules/flake-module.nix;
    };
}
