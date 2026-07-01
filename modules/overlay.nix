{ inputs, ... }: {
  perSystem = { system, ... }: {
    phenix.overlays = [
      (final: prev: {
        phenix = (prev.phenix or { }) // {
          nvim-nix = inputs.phenix-nvim.packages.${final.system}.nvim-nix;
        };
      })
    ];
  };
}
