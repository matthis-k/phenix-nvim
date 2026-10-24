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
    # Temporary opt-in integration preview of canonical provider runtime (#1135/#1136).
    # Promote only after exact-head runtime and editor product checks pass.
    phenix-ai.url = "github:matthis-k/phenix-ai/0da9e9d2dea92f7c074ec919825253462cc53d4d";
    phenix-ai-nvim = {
      url = "github:matthis-k/phenix-ai.nvim";
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
