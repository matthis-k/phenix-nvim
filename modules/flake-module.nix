{ ... }: {
  perSystem = { ... }: {
    phenix.overlays = [(final: prev: {
      phenix = (prev.phenix or {}) // {
        nvim-nix = final.writeShellScriptBin "nvim-nix" "exec nvim";
      };
    })];
  };
}
