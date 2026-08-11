{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      phenixConductor = inputs.phenix-acp.packages.${system}.phenix-conductor;
      phenixPlugin = pkgs.vimUtils.buildVimPlugin {
        pname = "phenix-nvim";
        version = "0";
        src = ../.;
        meta.description = "Minimal Neovim frontend for Phenix ACP";
      };

      nvimNix = inputs.nix-wrapper-modules.wrappers.neovim.wrap {
        inherit pkgs;
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
        runtimePkgs =
          with pkgs;
          [
            curl
            fd
            fzf
            gh
            git
            imagemagick
            lsof
          ]
          ++ [ phenixConductor ];
        specs.plugins.data = with pkgs.vimPlugins; [
          lz-n
          base16-nvim
          which-key-nvim
          nvim-web-devicons
          nui-nvim
          {
            name = "phenix-nvim";
            data = phenixPlugin;
            config = ''
              require("phenix").setup()
            '';
          }
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
        phenix-nvim-plugin = phenixPlugin;
      };
    };
}
