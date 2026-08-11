{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;

      phenixConductor = inputs.phenix-acp.packages.${system}.phenix-conductor;
      phenixPiAcp = inputs.phenix-acp.packages.${system}.pi-acp;
      phenixConfigFile = "${inputs.phenix-acp}/config/phenix-harness/init.lua";

      phenixPluginFiles = lib.fileset.unions [
        ../lua/phenix
        ../plugin/phenix.lua
      ];
      editorRuntimeFiles = lib.fileset.unions [
        ../after
        ../lsp
        ../lua
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
      pickResessionPlugin = pkgs.vimUtils.buildVimPlugin {
        pname = "pick-resession.nvim";
        version = "0";
        src = inputs.plugins-pick-resession-nvim;
      };

      nvimNix = inputs.nix-wrapper-modules.wrappers.neovim.wrap {
        inherit pkgs;
        binName = "nvim-nix";
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
        runtimePkgs =
          with pkgs;
          [
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
          ]
          ++ [
            phenixConductor
            phenixPiAcp
          ];
        runtimeLibs = [ pkgs.libgit2 ];
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
              require("phenix").setup({
                config_file = ${builtins.toJSON phenixConfigFile},
              })
            '';
          }
          snacks-nvim
          resession-nvim
          pickResessionPlugin
          nvim-lspconfig
          nvim-treesitter.withAllGrammars
          conform-nvim
          lazydev-nvim
          markview-nvim
          helpview-nvim
          gitsigns-nvim
          blink-cmp
          opencode-nvim
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
