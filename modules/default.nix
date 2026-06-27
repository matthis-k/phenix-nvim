_: {
  perSystem = { pkgs, ... }: {
    apps.default = {
      type = "app";
      program = "${pkgs.neovim}/bin/nvim";
    };
  };
}
