{ ... }: {
  perSystem = { ... }: {
    phenix.overlays = [(final: prev: {
      phenix = (prev.phenix or {}) // {};
    })];
  };
}
