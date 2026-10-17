{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;

      phenixAiNvim = inputs.phenix-ai-nvim.packages.${system}.phenix-ai-nvim;
      phenixAiNvimBasic = inputs.phenix-ai-nvim.packages.${system}.phenix-ai-nvim-basic;
      phenixAiNvimLive = inputs.phenix-ai-nvim.packages.${system}.phenix-ai-nvim-live;
      neovim = inputs.neovim-nightly.packages.${system}.default;

      editorRuntimeFiles = lib.fileset.unions [
        ../after
        ../lsp
        ../lua
        ../pack
        ../plugin
      ];
      editorConfigSource = lib.fileset.toSource {
        root = ../.;
        fileset = editorRuntimeFiles;
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

      # Both distributions consume the same frontend. Only the selected
      # upstream client artifact and executable name differ.
      mkNeovim =
        aiClient: binaryName:
        inputs.nix-wrapper-modules.wrappers.neovim.wrap {
          inherit pkgs;
          package = neovim;
          binName = binaryName;
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
            ripgrep
            rust-analyzer
            stylua
            taplo
            typescript-language-server
            vscode-langservers-extracted
            wl-clipboard
            xclip
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
            phenix-ai = {
              name = "phenix-ai.nvim";
              data = aiClient;
              config = ''
                require("phenix_nvim").setup({ auto_connect = true })
              '';
            };
          };
        };
      nvimNix = mkNeovim phenixAiNvim "nvim-nix";
      nvimNixBasic = mkNeovim phenixAiNvimBasic "nvim-nix-basic";
      nvimNixLive = mkNeovim phenixAiNvimLive "nvim-nix-live";
      livePrompt = pkgs.writeShellApplication {
        name = "phenix-p1-live-prompt";
        text = ''
          if [ "$#" -eq 0 ]; then
            echo "Usage: phenix-p1-live-prompt PROMPT..." >&2
            echo "Supply OPENAI_API_KEY or PHENIX_MODEL_HTTP_API_KEY at runtime." >&2
            exit 2
          fi
          export PHENIX_P1_PROMPT="$*"
          exec ${nvimNixLive}/bin/nvim-nix-live --headless \
            -l ${phenixAiNvimLive}/share/phenix-ai.nvim/p1_live_prompt.lua
        '';
      };
    in
    {
      packages = {
        default = nvimNix;
        nvim-nix = nvimNix;
        # This distribution's lock now requires the M1/P1 client closure.
        nvim-nix-basic = nvimNixBasic;
        nvim-nix-live = nvimNixLive;
        phenix-p1-live-prompt = livePrompt;
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
      }
;
    };
}
