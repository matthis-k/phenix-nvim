{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;

      phenixConductor = inputs.phenix-acp.packages.${system}.phenix-conductor;
      phenixPiAcp = inputs.phenix-acp.packages.${system}.pi-acp;
      phenixConfigFile = "${inputs.phenix-acp}/config/phenix-harness/init.lua";
      neovim = inputs.neovim-nightly.packages.${system}.default;

      phenixPluginFiles = lib.fileset.unions [
        ../lua/phenix
        ../plugin/phenix.lua
      ];
      editorRuntimeFiles = lib.fileset.unions [
        ../after
        ../lsp
        ../lua
        ../pack
        ../plugin
      ];
      phenixPluginSource = lib.fileset.toSource {
        root = ../.;
        fileset = phenixPluginFiles;
      };
      editorConfigSource = lib.fileset.toSource {
        root = ../.;
        fileset = lib.fileset.difference editorRuntimeFiles phenixPluginFiles;
      };

      phenixPlugin = pkgs.vimUtils.buildVimPlugin {
        pname = "phenix-nvim";
        version = "0";
        src = phenixPluginSource;
        meta.description = "Minimal Neovim frontend for Phenix ACP";
      };
      phenixBarsPlugin = pkgs.vimUtils.buildVimPlugin {
        pname = "phenix-bars.nvim";
        version = "0";
        src = ../pack/phenix/opt/phenix-bars;
        meta.description = "Composable statusline, tabline, and statuscolumn primitives";
      };
      phenixColorPreviewPlugin = pkgs.vimUtils.buildVimPlugin {
        pname = "phenix-color-preview.nvim";
        version = "0";
        src = ../pack/phenix/opt/phenix-color-preview;
        meta.description = "Configurable Neovim palette preview";
      };
      pickResessionPlugin = pkgs.vimUtils.buildVimPlugin {
        pname = "pick-resession.nvim";
        version = "0";
        src = inputs.plugins-pick-resession-nvim;
      };
      nvimNix = inputs.nix-wrapper-modules.wrappers.neovim.wrap {
        inherit pkgs;
        package = neovim;
        binName = "nvim-nix";
        env.VIMRUNTIME = "${neovim}/share/nvim/runtime";
        settings = {
          config_directory = toString editorConfigSource;
          aliases = [
            "vi"
            "vim"
          ];
          nvim_lua_env = luaPackages: [
            luaPackages.fzy
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
        runtimePkgs = with pkgs; [
          clang-tools
          curl
          fd
          fzf
          gh
          git
          imagemagick
          kdePackages.qtdeclarative
          lemminx
          lsof
          lua-language-server
          luarocks
          lua5_1
          marksman
          nil
          nixfmt
          opencode
          ripgrep
          rust-analyzer
          stylua
          taplo
          typescript-language-server
          vscode-langservers-extracted
          phenixConductor
          phenixPiAcp
        ];
        runtimeLibs = [ pkgs.libgit2 ];
        specs = with pkgs.vimPlugins; {
          dependencies.data = [
            base16-nvim
            blink-cmp
            conform-nvim
            gitsigns-nvim
            helpview-nvim
            lazydev-nvim
            markview-nvim
            nui-nvim
            nvim-lspconfig
            nvim-treesitter.withAllGrammars
            nvim-web-devicons
            opencode-nvim
            pickResessionPlugin
            resession-nvim
            snacks-nvim
            telescope-nvim
            which-key-nvim
          ];
          phenix = {
            name = "phenix-nvim";
            data = phenixPlugin;
            config = ''
              require("phenix").setup({
                config_file = ${builtins.toJSON phenixConfigFile},
              })
            '';
          };
        };
      };
    in
    {
      packages = {
        default = nvimNix;
        nvim-nix = nvimNix;
        phenix-nvim-plugin = phenixPlugin;
        phenix-bars-plugin = phenixBarsPlugin;
        phenix-color-preview-plugin = phenixColorPreviewPlugin;
      };
    };
}
