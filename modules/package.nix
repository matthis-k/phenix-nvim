{ inputs, lib, ... }:
let
  inherit (inputs) nix-wrapper-modules;
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      nvimNix = nix-wrapper-modules.wrappers.neovim.wrap {
        inherit pkgs;
        binName = "nvim-nix";
        settings = {
          config_directory = ../.;
          use_nix_managed_plugins = true;
          nvim_lua_env = lp: [
            lp.magick
            lp.luautf8
          ];
        };
        hosts = {
          python3.nvim-host.enable = true;
          node.nvim-host.enable = true;
          ruby.nvim-host.enable = true;
          perl.nvim-host.enable = true;
        };
        runtimePkgs = with pkgs; [
          curl
          fd
          fzf
          gh
          git
          imagemagick
          lsof
        ];
        specs.plugins.data = with pkgs.vimPlugins; [
          lz-n
          base16-nvim
          which-key-nvim
          nvim-web-devicons
          nui-nvim
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
          opencode-nvim
          telescope-nvim
        ];
      };
    in
    {
      packages = {
        default = nvimNix;
        nvim-nix = nvimNix;
      };

      devShells.default = pkgs.mkShell {
        name = "phenix-nvim-dev";
        packages = with pkgs; [
          nix
          nixfmt
          statix
          deadnix
          inputs.phenix-tend.packages.${pkgs.system}.tend
        ];
        shellHook = ''
          repo-hook() {
            if command -v tend &>/dev/null; then
              tend check --profile git-hook --staged "$@"
            else
              echo "tend not available — enter the root Phenix dev shell" >&2
              return 1
            fi
          }
          repo-pushgate() {
            if command -v tend &>/dev/null; then
              tend check --profile pre-push "$@"
            else
              echo "tend not available — enter the root Phenix dev shell" >&2
              return 1
            fi
          }
          repo-check() {
            if command -v tend &>/dev/null; then
              tend check --profile manual "$@"
            else
              echo "tend not available — enter the root Phenix dev shell" >&2
              return 1
            fi
          }
          repo-fix() {
            if command -v tend &>/dev/null; then
              tend check --profile fix "$@"
            else
              echo "tend not available — enter the root Phenix dev shell" >&2
              return 1
            fi
          }
          export -f repo-hook repo-pushgate repo-check repo-fix 2>/dev/null || true
          echo "phenix-nvim dev shell"
          echo "  tools: nix nixfmt statix deadnix"
          if command -v tend &>/dev/null; then
            echo "  repo-hook      -> tend check --profile git-hook --staged"
            echo "  repo-pushgate  -> tend check --profile pre-push"
            echo "  repo-check     -> tend check --profile manual"
            echo "  repo-fix       -> tend check --profile fix"
          fi
        '';
      };
    };
}
