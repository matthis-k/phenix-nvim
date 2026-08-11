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
        runtimePkgs =
          with phenixPkgs;
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
        specs.plugins.data = with phenixPkgs.vimPlugins; [
          lz-n
          base16-nvim
          which-key-nvim
          nvim-web-devicons
          nui-nvim
          {
            name = "phenix-nvim";
            data = phenix-nvim;
            config = ''
              local phenix = require("phenix")
              phenix.setup()

              local function map(lhs, rhs, desc)
                vim.keymap.set("n", lhs, rhs, {
                  desc = "Phenix: " .. desc,
                  silent = true,
                })
              end

              map("<leader>po", "<cmd>PhenixOpen<cr>", "open session")
              map("<leader>pn", "<cmd>PhenixNew<cr>", "new session")
              map("<leader>pp", "<cmd>PhenixPrompt<cr>", "prompt / focus composer")
              map("<leader>pc", "<cmd>PhenixConfig<cr>", "configure session")
              map("<leader>px", "<cmd>PhenixCancel<cr>", "cancel prompt")
              map("<leader>pq", "<cmd>PhenixClose<cr>", "close session")

              require("which-key").add({
                { "<leader>p", group = "Phenix" },
              })
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
      };
    };
}
