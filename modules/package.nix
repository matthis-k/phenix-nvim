{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;

      phenixConductor = inputs.phenix-acp.packages.${system}.phenix-conductor;
      piAcpVersion = "0.0.33";
      piAcpSource = pkgs.fetchFromGitHub {
        owner = "svkozak";
        repo = "pi-acp";
        rev = "d1cffc047ab37a096ee70ca39cfc1de463db8d12";
        hash = lib.fakeHash;
      };
      phenixPiAcp = pkgs.buildNpmPackage {
        pname = "pi-acp";
        version = piAcpVersion;
        src = piAcpSource;
        npmDepsHash = lib.fakeHash;
      };
      phenixFrontendConductor = pkgs.writeShellScriptBin "phenix-conductor-nvim" ''
        export PATH=${lib.makeBinPath [ pkgs.pi-coding-agent ]}:$PATH
        exec ${phenixConductor}/bin/phenix-conductor \
          --acp-command ${phenixPiAcp}/bin/pi-acp \
          --acp-backend pi \
          --acp-provider pi \
          "$@"
      '';
      neovim = inputs.neovim-nightly.packages.${system}.default;

      phenixFrontendFiles = lib.fileset.unions [
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
      phenixFrontendSource = lib.fileset.toSource {
        root = ../.;
        fileset = phenixFrontendFiles;
      };
      editorConfigSource = lib.fileset.toSource {
        root = ../.;
        fileset = lib.fileset.difference editorRuntimeFiles phenixFrontendFiles;
      };

      phenixFrontendPlugin = pkgs.vimUtils.buildVimPlugin {
        pname = "phenix-nvim";
        version = "0";
        src = phenixFrontendSource;
        dependencies = [ phenixUiPlugin ];
        meta.description = "Neovim frontend for the Phenix conductor";
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
          # The frontend must use the fully composed conductor product rather
          # than launching the backend-neutral conductor with an empty catalog.
          PHENIX_CONDUCTOR_COMMAND = "${phenixFrontendConductor}/bin/phenix-conductor-nvim";
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
          pi-coding-agent
          ripgrep
          rust-analyzer
          stylua
          taplo
          typescript-language-server
          vscode-langservers-extracted
          wl-clipboard
          xclip
          phenixConductor
          phenixFrontendConductor
          phenixPiAcp
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
          phenix = {
            name = "phenix";
            data = phenixFrontendPlugin;
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
        phenix-frontend-plugin = phenixFrontendPlugin;
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
