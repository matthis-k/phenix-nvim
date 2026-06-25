{ ... }: {
  phenix.overlays = [(final: prev: {
    phenix = (prev.phenix or {}) // {
      hello-nvim = final.writeShellScriptBin "hello-nvim" ''
        echo "hello from nvim"
      '';
    };
  })];
}
