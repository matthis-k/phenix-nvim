{
  description = "Phenix Neovim configuration";

  inputs = {
    phenix-pins.url = "github:matthis-k/phenix-pins";
    nixpkgs.follows = "phenix-pins/nixpkgs";
  };

  outputs = inputs: { };
}
