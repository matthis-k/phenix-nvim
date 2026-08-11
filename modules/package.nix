{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      phenixPkgs = pkgs.extend inputs.phenix-agent-harness.overlays.default;
      phenixConductor = inputs.phenix-agent-harness.packages.${system}.phenix-conductor;

      nvimNix = inputs.nix-wrapper-modules.wrappers.neovim.wrap {
        pkgs = phenixPkgs;
        binName = "nvim-nix";
        settings = {
          config_directory = ../.;
          use_nix_managed_plugins = true;
          nvim_lua_env = luaPackages: [
            luaPackages.magick
            luaPackages.luautf8
          ];
        };
        hosts = {
          python3.nvim-host.enable = true;
          node.nvim-host.enable = true;
          ruby.nvim-host.enable = true;
          perl.nvim-host.enable = true;
        };
        runtimePkgs = with phenixPkgs; [
          curl
          fd
          fzf
          gh
          git
          imagemagick
          lsof
        ] ++ [ phenixConductor ];
        specs.plugins.data = with phenixPkgs.vimPlugins; [
          lz-n
          base16-nvim
          which-key-nvim
          nvim-web-devicons
          nui-nvim
          phenix-nvim
          snacks-nvim
          resession-nvim
          nvim-lspconfig
          nvim-treesitter.withAllGrammars
          conform-nvim
          lazydev-nvim
          markview-nvim
          helpview-nvim
          gitsigns-nvim
          blink-cmp
          telescope-nvim
        ];
      };
    in
    {
      packages = {
        default = nvimNix;
        nvim-nix = nvimNix;
      };
    };
}
