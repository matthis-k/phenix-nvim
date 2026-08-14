{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;

      phenixConductor = inputs.phenix-acp.packages.${system}.phenix-conductor;
      phenixConfigSource = lib.fileset.toSource {
        root = ../config;
        fileset = ../config;
      };
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
        dependencies = [ phenixUiPlugin ];
        meta.description = "Neovim frontend wrapper for the Phenix ACP harness";
      };
      mkFeature =
        {
          pname,
          src,
          description,
        }:
        pkgs.vimUtils.buildVimPlugin {
          inherit pname src;
          version = "0";
          meta.description = description;
        };
      phenixUiPlugin = mkFeature {
        pname = "phenix-ui.nvim";
        src = ../pack/phenix/opt/phenix-ui;
        description = "Shared typed frontend API facade and UI utilities";
      };
      phenixBarsPlugin = mkFeature {
        pname = "phenix-bars.nvim";
        src = ../pack/phenix/opt/phenix-bars;
        description = "Composable statusline, tabline, and statuscolumn primitives";
      };
      phenixColorPreviewPlugin = mkFeature {
        pname = "phenix-color-preview.nvim";
        src = ../pack/phenix/opt/phenix-color-preview;
        description = "Configurable palette preview";
      };
      phenixPickerPlugin = mkFeature {
        pname = "phenix-picker.nvim";
        src = ../pack/phenix/opt/phenix-picker;
        description = "Typed picker frontend";
      };
      phenixSessionPlugin = mkFeature {
        pname = "phenix-session.nvim";
        src = ../pack/phenix/opt/phenix-session;
        description = "Session lifecycle frontend";
      };
      phenixThemePlugin = mkFeature {
        pname = "phenix-theme.nvim";
        src = ../pack/phenix/opt/phenix-theme;
        description = "Phenix editor theme";
      };
      phenixGitPlugin = mkFeature {
        pname = "phenix-git.nvim";
        src = ../pack/phenix/opt/phenix-git;
        description = "Git editor integration";
      };
      phenixLspPlugin = mkFeature {
        pname = "phenix-lsp.nvim";
        src = ../pack/phenix/opt/phenix-lsp;
        description = "LSP editor integration";
      };
      phenixCompletionPlugin = mkFeature {
        pname = "phenix-completion.nvim";
        src = ../pack/phenix/opt/phenix-completion;
        description = "Completion integration";
      };
      phenixDashboardPlugin = mkFeature {
        pname = "phenix-dashboard.nvim";
        src = ../pack/phenix/opt/phenix-dashboard;
        description = "Dashboard frontend";
      };
      phenixExplorerPlugin = mkFeature {
        pname = "phenix-explorer.nvim";
        src = ../pack/phenix/opt/phenix-explorer;
        description = "Explorer frontend";
      };
      phenixTerminalPlugin = mkFeature {
        pname = "phenix-terminal.nvim";
        src = ../pack/phenix/opt/phenix-terminal;
        description = "Terminal frontend";
      };
      phenixNotifyPlugin = mkFeature {
        pname = "phenix-notify.nvim";
        src = ../pack/phenix/opt/phenix-notify;
        description = "Notification frontend";
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
        env = {
          VIMRUNTIME = "${neovim}/share/nvim/runtime";
          PHENIX_CONFIG_DIR = "${phenixConfigSource}/phenix";
          # The frontend must use the conductor paired with this wrapper rather
          # than a potentially stale command inherited through PATH.
          PHENIX_CONDUCTOR_COMMAND = "${phenixConductor}/bin/phenix-conductor";
        };
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
          ripgrep
          rust-analyzer
          stylua
          taplo
          typescript-language-server
          vscode-langservers-extracted
          wl-clipboard
          xclip
          phenixConductor
        ];
        runtimeLibs = [ pkgs.libgit2 ];
        specs = with pkgs.vimPlugins; {
          dependencies.data = [
            phenixUiPlugin
            base16-nvim
            blink-cmp
            conform-nvim
            gitsigns-nvim
            helpview-nvim
            lazydev-nvim
            lz-n
            markview-nvim
            nui-nvim
            nvim-lspconfig
            nvim-treesitter.withAllGrammars
            nvim-web-devicons
            pickResessionPlugin
            resession-nvim
            snacks-nvim
            telescope-nvim
            which-key-nvim
          ];
          phenix-acp = {
            name = "phenix-acp";
            data = phenixAcpPlugin;
            config = ''
              require("phenix").setup()
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
