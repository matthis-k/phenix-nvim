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

      phenixAcpFiles = lib.fileset.unions [
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
      phenixAcpSource = lib.fileset.toSource {
        root = ../.;
        fileset = phenixAcpFiles;
      };
      editorConfigSource = lib.fileset.toSource {
        root = ../.;
        fileset = lib.fileset.difference editorRuntimeFiles phenixAcpFiles;
      };

      phenixAcpPlugin = pkgs.vimUtils.buildVimPlugin {
        pname = "phenix-acp.nvim";
        version = "0";
        src = phenixAcpSource;
        meta.description = "Neovim frontend wrapper for the Phenix ACP harness";
      };
      mkFeature = pname: src: description: pkgs.vimUtils.buildVimPlugin {
        inherit pname src;
        version = "0";
        meta.description = description;
      };
      phenixUiPlugin = mkFeature "phenix-ui.nvim" ../pack/phenix/opt/phenix-ui "Shared typed frontend interfaces and UI utilities";
      phenixBarsPlugin = mkFeature "phenix-bars.nvim" ../pack/phenix/opt/phenix-bars "Composable statusline, tabline, and statuscolumn primitives";
      phenixColorPreviewPlugin = mkFeature "phenix-color-preview.nvim" ../pack/phenix/opt/phenix-color-preview "Configurable palette preview";
      phenixPickerPlugin = mkFeature "phenix-picker.nvim" ../pack/phenix/opt/phenix-picker "Typed picker frontend";
      phenixSessionPlugin = mkFeature "phenix-session.nvim" ../pack/phenix/opt/phenix-session "Session lifecycle frontend";
      phenixThemePlugin = mkFeature "phenix-theme.nvim" ../pack/phenix/opt/phenix-theme "Phenix editor theme";
      phenixGitPlugin = mkFeature "phenix-git.nvim" ../pack/phenix/opt/phenix-git "Git editor integration";
      phenixLspPlugin = mkFeature "phenix-lsp.nvim" ../pack/phenix/opt/phenix-lsp "LSP editor integration";
      phenixCompletionPlugin = mkFeature "phenix-completion.nvim" ../pack/phenix/opt/phenix-completion "Completion integration";
      phenixDashboardPlugin = mkFeature "phenix-dashboard.nvim" ../pack/phenix/opt/phenix-dashboard "Dashboard frontend";
      phenixExplorerPlugin = mkFeature "phenix-explorer.nvim" ../pack/phenix/opt/phenix-explorer "Explorer frontend";
      phenixTerminalPlugin = mkFeature "phenix-terminal.nvim" ../pack/phenix/opt/phenix-terminal "Terminal frontend";
      phenixNotifyPlugin = mkFeature "phenix-notify.nvim" ../pack/phenix/opt/phenix-notify "Notification frontend";
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
          aliases = [ "vi" "vim" ];
          nvim_lua_env = luaPackages: [ luaPackages.fzy luaPackages.magick luaPackages.luautf8 ];
        };
        hosts = {
          python3.nvim-host.enable = true;
          node.nvim-host.enable = true;
          ruby.nvim-host.enable = true;
          perl.nvim-host.enable = true;
        };
        runtimePkgs = with pkgs; [
          clang-tools curl fd fzf gh git imagemagick kdePackages.qtdeclarative lemminx lsof
          lua-language-server luarocks lua5_1 marksman nil nixfmt ripgrep rust-analyzer stylua taplo
          typescript-language-server vscode-langservers-extracted phenixConductor phenixPiAcp
        ];
        runtimeLibs = [ pkgs.libgit2 ];
        specs = with pkgs.vimPlugins; {
          dependencies.data = [
            base16-nvim blink-cmp conform-nvim gitsigns-nvim helpview-nvim lazydev-nvim markview-nvim
            nui-nvim nvim-lspconfig nvim-treesitter.withAllGrammars nvim-web-devicons pickResessionPlugin
            resession-nvim snacks-nvim telescope-nvim which-key-nvim
          ];
          phenix-acp = {
            name = "phenix-acp";
            data = phenixAcpPlugin;
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
        phenix-acp-plugin = phenixAcpPlugin;
        phenix-ui-plugin = phenixUiPlugin;
        phenix-bars-plugin = phenixBarsPlugin;
        phenix-color-preview-plugin = phenixColorPreviewPlugin;
        phenix-picker-plugin = phenixPickerPlugin;
        phenix-session-plugin = phenixSessionPlugin;
        phenix-theme-plugin = phenixThemePlugin;
        phenix-git-plugin = phenixGitPlugin;
        phenix-lsp-plugin = phenixLspPlugin;
        phenix-completion-plugin = phenixCompletionPlugin;
        phenix-dashboard-plugin = phenixDashboardPlugin;
        phenix-explorer-plugin = phenixExplorerPlugin;
        phenix-terminal-plugin = phenixTerminalPlugin;
        phenix-notify-plugin = phenixNotifyPlugin;
      };
    };
}
