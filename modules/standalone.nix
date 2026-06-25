{ inputs, lib, ... }: let
  nix-wrapper-modules = inputs.nix-wrapper-modules;
in {
  perSystem = { pkgs, system, ... }: let
    nvimNix = nix-wrapper-modules.wrappers.neovim.wrap {
      inherit pkgs;
      binName = "nvim-nix";
      settings = {
        config_directory = ../configs/nvim;
        use_nix_managed_plugins = true;
        nvim_lua_env = lp: [ lp.magick lp.luautf8 ];
      };
      hosts = {
        python3.nvim-host.enable = true;
        node.nvim-host.enable = true;
        ruby.nvim-host.enable = true;
        perl.nvim-host.enable = true;
      };
      runtimePkgs = with pkgs; [ curl fd fzf gh git imagemagick lsof ];
      specs.plugins.data = with pkgs.vimPlugins; [
        lz-n base16-nvim which-key-nvim nvim-web-devicons nui-nvim
        snacks-nvim resession-nvim nvim-lspconfig
        (nvim-treesitter.withAllGrammars)
        conform-nvim lazydev-nvim markview-nvim helpview-nvim gitsigns-nvim
        blink-cmp opencode-nvim telescope-nvim
      ];
    };
  in {
    packages = {
      default = nvimNix;
      nvim-nix = nvimNix;
    };
  };
}
