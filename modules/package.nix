{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
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
          telescope-nvim
        ];
      };

      startupCheck = pkgs.runCommand "phenix-nvim-startup" { nativeBuildInputs = [ nvimNix ]; } ''
        export HOME="$TMPDIR/home"
        export XDG_CACHE_HOME="$TMPDIR/cache"
        export XDG_CONFIG_HOME="$TMPDIR/config"
        export XDG_DATA_HOME="$TMPDIR/data"
        export XDG_STATE_HOME="$TMPDIR/state"
        mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

        nvim-nix --headless '+qa'
        touch "$out"
      '';
    in
    {
      packages = {
        default = nvimNix;
        nvim-nix = nvimNix;
      };
      checks.nvim-startup = startupCheck;
    };
}
