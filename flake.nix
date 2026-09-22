{
  description = "Phenix Neovim distribution";

  inputs = {
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    phenix-pins = {
      url = "github:matthis-k/phenix-pins";
      inputs.phenix-flake-ci.follows = "phenix-flake-ci";
    };
    phenix-flake-ci.url = "github:matthis-k/phenix-flake-ci";
    neovim-nightly = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    phenix-ai = {
      url = "github:matthis-k/phenix-ai/d7e19ea54947c65b43c1d9345c1d19972b3811a9";
      inputs.phenix-pins.follows = "phenix-pins";
      inputs.phenix-flake-ci.follows = "phenix-flake-ci";
    };
    phenix-ai-nvim = {
      url = "github:matthis-k/phenix-ai.nvim/2d3ec449339960db15cda48c030904a8ef7902c1";
      inputs.phenix-ai.follows = "phenix-ai";
    };
    nixpkgs.follows = "phenix-pins/nixpkgs";
    nix-wrapper-modules = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plugins-pick-resession-nvim = {
      url = "github:scottmckendry/pick-resession.nvim";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      imports = [
        ./modules/outputs.nix
        ./modules/package.nix
        ./modules/development.nix
      ];
      flake.flakeModules.default = import ./modules/overlay.nix;
    };
}
