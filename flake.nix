{
  description = "Phenix Neovim configuration";

  inputs = {
    phenix-pins.url = "github:matthis-k/phenix-pins";
    phenix-packages.url = "github:matthis-k/phenix-packages";
    nixpkgs.follows = "phenix-pins/nixpkgs";
  };

  outputs = inputs: {
    apps.x86_64-linux.default = {
      type = "app";
      program = "${(import inputs.nixpkgs {
        system = "x86_64-linux";
      }).neovim}/bin/nvim";
    };

    apps.aarch64-linux.default = {
      type = "app";
      program = "${(import inputs.nixpkgs {
        system = "aarch64-linux";
      }).neovim}/bin/nvim";
    };
  };
}
