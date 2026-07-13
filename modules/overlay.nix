{ inputs, ... }:
{
  perSystem = {
    phenix.overlays = [ inputs.phenix-nvim.overlays.default ];
  };
}
