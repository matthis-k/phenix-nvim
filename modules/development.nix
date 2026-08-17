{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      maintenanceLib = inputs.phenix-flake-ci.lib;
      repositoryRoot = ''
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
        cd "$repo_root"
      '';

      sourceCi = {
        enable = true;
        stage = "source";
        name = "Source";
        timeoutMinutes = 30;
      };
      productCi = {
        enable = true;
        stage = "product";
        name = "Product";
        timeoutMinutes = 30;
        needs = [ "source" ];
      };

      maintenance = maintenanceLib.mkMaintenance {
        name = "maintenance";
        description = "Phenix Neovim maintenance";
        ci.github = {
          enable = true;
          outputName = "phenix-maintenance";
        };
        gitHooks = {
          enable = true;
          preCommit = [ "fix" ];
        };

        commands = {
          all = {
            description = "Run the complete validation graph";
            exec = ''
              "$0" check
              "$0" test
            '';
          };

          check = {
            description = "Run source validation";
            order = [
              "nix-format"
              "statix"
              "deadnix"
              "actionlint"
              "workflow-sync"
            ];
            commands = {
              nix-format = {
                description = "Nix formatting";
                ci = sourceCi // {
                  stepName = "Nix formatting";
                };
                runtimeInputs = pkgs: [
                  pkgs.findutils
                  pkgs.git
                  pkgs.nixfmt
                ];
                exec = ''
                  ${repositoryRoot}
                  find . -type f -name '*.nix' \
                    -not -path './.git/*' \
                    -print0 |
                    xargs -0 -r nixfmt --check
                '';
              };

              statix = {
                description = "Nix static analysis";
                ci = sourceCi // {
                  stepName = "Statix";
                };
                runtimeInputs = pkgs: [
                  pkgs.git
                  pkgs.statix
                ];
                exec = ''
                  ${repositoryRoot}
                  statix check --ignore '.git/**'
                '';
              };

              deadnix = {
                description = "Unused Nix code";
                ci = sourceCi // {
                  stepName = "Deadnix";
                };
                runtimeInputs = pkgs: [
                  pkgs.deadnix
                  pkgs.git
                ];
                exec = ''
                  ${repositoryRoot}
                  deadnix --fail --no-lambda-arg --no-lambda-pattern-names
                '';
              };

              actionlint = {
                description = "GitHub Actions syntax";
                ci = sourceCi // {
                  stepName = "Actionlint";
                };
                runtimeInputs = pkgs: [
                  pkgs.actionlint
                  pkgs.findutils
                  pkgs.git
                ];
                exec = ''
                  ${repositoryRoot}
                  find .github/workflows -type f \
                    \( -name '*.yml' -o -name '*.yaml' \) -print0 |
                    xargs -0 -r actionlint
                '';
              };

              workflow-sync = {
                description = "Committed workflow matches the maintenance declaration";
                ci = sourceCi // {
                  stepName = "Generated workflow";
                };
                runtimeInputs = pkgs: [
                  pkgs.diffutils
                  pkgs.git
                  pkgs.nix
                ];
                exec = ''
                  ${repositoryRoot}
                  system="$(nix eval --impure --raw --expr builtins.currentSystem)"
                  generated="$(mktemp)"
                  trap 'rm -f "$generated"' EXIT
                  nix eval --raw \
                    ".#packages.$system.phenix-maintenance.phenixMaintenance.ci.github.workflow" \
                    > "$generated"
                  diff -u .github/workflows/ci.yml "$generated"
                '';
              };
            };
          };

          test = {
            description = "Run functional editor tests";
            order = [
              "plugin"
              "socket"
              "startup"
            ];
            commands = {
              plugin = {
                description = "Exercise live session semantics against a deterministic native conductor fixture";
                ci = productCi // {
                  stepName = "Neovim plugin smoke";
                };
                runtimeInputs = pkgs: [
                  pkgs.git
                  pkgs.nix
                  pkgs.python3
                ];
                exec = ''
                  ${repositoryRoot}
                  tmp="$(mktemp -d)"
                  trap 'rm -rf "$tmp"' EXIT
                  export PHENIX_TEST_PYTHON="${pkgs.python3}/bin/python3"
                  HOME="$tmp/home" \
                  XDG_CACHE_HOME="$tmp/cache" \
                  XDG_CONFIG_HOME="$tmp/config" \
                  XDG_DATA_HOME="$tmp/data" \
                  XDG_STATE_HOME="$tmp/state" \
                    nix run .#nvim-nix -- --headless \
                      "+lua dofile('$repo_root/tests/smoke.lua')" \
                      '+qa!'
                '';
              };

              socket = {
                description = "Connect the packaged frontend to a persistent local conductor socket without owning its lifetime";
                ci = productCi // {
                  stepName = "Persistent conductor socket transport";
                };
                runtimeInputs = pkgs: [
                  pkgs.git
                  pkgs.nix
                ];
                exec = ''
                  ${repositoryRoot}
                  tmp="$(mktemp -d)"
                  trap 'rm -rf "$tmp"' EXIT
                  HOME="$tmp/home" \
                  XDG_CACHE_HOME="$tmp/cache" \
                  XDG_CONFIG_HOME="$tmp/config" \
                  XDG_DATA_HOME="$tmp/data" \
                  XDG_STATE_HOME="$tmp/state" \
                    nix run .#nvim-nix -- --headless \
                      "+lua local ok, err = pcall(dofile, '$repo_root/tests/socket_transport.lua'); if not ok then vim.api.nvim_err_writeln(tostring(err)); vim.cmd('cq') end" \
                      '+qa!'
                '';
              };

              startup = {
                description = "Initialize the packaged frontend against the native conductor protocol";
                ci = productCi // {
                  stepName = "Native conductor startup";
                };
                runtimeInputs = pkgs: [
                  pkgs.git
                  pkgs.nix
                  pkgs.python3
                ];
                exec = ''
                  ${repositoryRoot}
                  tmp="$(mktemp -d)"
                  trap 'rm -rf "$tmp"' EXIT
                  export PHENIX_TEST_PYTHON="${pkgs.python3}/bin/python3"
                  HOME="$tmp/home" \
                  XDG_CACHE_HOME="$tmp/cache" \
                  XDG_CONFIG_HOME="$tmp/config" \
                  XDG_DATA_HOME="$tmp/data" \
                  XDG_STATE_HOME="$tmp/state" \
                    nix run .#nvim-nix -- --headless \
                      "+lua local ok, err = pcall(dofile, '$repo_root/tests/startup.lua'); if not ok then vim.api.nvim_err_writeln(tostring(err)); vim.cmd('cq') end" \
                      '+qa!'
                '';
              };
            };
          };

          fix = {
            description = "Apply deterministic Nix normalization";
            runtimeInputs = pkgs: [
              pkgs.deadnix
              pkgs.findutils
              pkgs.git
              pkgs.nixfmt
              pkgs.statix
            ];
            exec = ''
              ${repositoryRoot}
              statix fix
              deadnix --edit --no-lambda-arg --no-lambda-pattern-names
              find . -type f -name '*.nix' \
                -not -path './.git/*' \
                -print0 |
                xargs -0 -r nixfmt
            '';
          };
        };
      };

      maintenancePackage = maintenanceLib.mkMaintenancePackage {
        inherit pkgs maintenance;
      };
    in
    {
      packages.phenix-maintenance = maintenancePackage.package;
      apps.phenix-maintenance = maintenancePackage.app;

      devShells.default = pkgs.mkShell {
        name = "phenix-nvim-dev";
        packages = [
          pkgs.git
          pkgs.nix
          maintenancePackage.package
        ];
        shellHook = ''
          ${maintenancePackage.shellHook}

          echo "phenix-nvim dev shell"
          echo "  all:    maintenance all"
          echo "  check:  maintenance check"
          echo "  test:   maintenance test"
          echo "  fixes:  maintenance fix"
        '';
      };
    };
}
