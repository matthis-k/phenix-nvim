{ inputs, ... }:
{
  flake.overlays.default = final: prev: {
    vimPlugins = prev.vimPlugins // {
      phenix-nvim = inputs.self.packages.${final.system}.phenix-nvim-plugin;
    };
    phenix = (prev.phenix or { }) // {
      nvim-nix = inputs.self.packages.${final.system}.nvim-nix;
    };
  };
}
