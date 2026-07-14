{ inputs, ... }:
{
  flake.overlays.default = final: prev: {
    phenix = (prev.phenix or { }) // {
      nvim-nix = inputs.self.packages.${final.system}.nvim-nix;
    };
  };
}
