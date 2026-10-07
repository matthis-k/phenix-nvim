{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      maintenanceLib = inputs.phenix-flake-ci.lib;
      phenixAiNvim = inputs.phenix-ai-nvim.packages.${system}.phenix-ai-nvim;
      phenixAiRevision = inputs.phenix-ai.rev or "dirty";
      repositoryRoot = ''
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
        cd "$repo_root"
      '';

      maintenance = maintenanceLib.mkMaintenance {
        name = "maintenance";
        description = "Phenix Neovim distribution maintenance";
        gitHooks = {
          enable = true;
          preCommit = [ "fix" ];
        };

        commands = {
          all = {
            description = "Run source and distribution validation";
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
            ];
            commands = {
              nix-format = {
                description = "Nix formatting";
                runtimeInputs = pkgs: [
                  pkgs.findutils
                  pkgs.git
                  pkgs.nixfmt
                ];
                exec = ''
                  ${repositoryRoot}
                  find . -type f -name '*.nix' -not -path './.git/*' -print0 |
                    xargs -0 -r nixfmt --check
                '';
              };
              statix = {
                description = "Nix static analysis";
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
            };
          };

          test = {
            description = "Smoke-test packaged Neovim distribution configuration";
            runtimeInputs = pkgs: [
              pkgs.git
              pkgs.nix
            ];
            exec = ''
              ${repositoryRoot}
              test "$(cat ${phenixAiNvim}/share/phenix-ai.nvim/phenix-ai-revision)" = \
                ${pkgs.lib.escapeShellArg phenixAiRevision}
              tmp="$(mktemp -d)"
              trap 'rm -rf "$tmp"' EXIT
              HOME="$tmp/home" \
              XDG_CACHE_HOME="$tmp/cache" \
              XDG_CONFIG_HOME="$tmp/config" \
              XDG_DATA_HOME="$tmp/data" \
              XDG_STATE_HOME="$tmp/state" \
                nix run .#nvim-nix -- --headless \
                  "+lua local ok, err = pcall(dofile, '$repo_root/tests/distribution.lua'); if not ok then io.stderr:write(tostring(err)); vim.cmd('cquit 1') end" \
                  '+qa!'
            '';
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
              find . -type f -name '*.nix' -not -path './.git/*' -print0 |
                xargs -0 -r nixfmt
            '';
          };
        };
      };

      maintenancePackage = maintenanceLib.mkMaintenancePackage {
        inherit pkgs maintenance;
      };
      sourceMaintenancePackage = maintenanceLib.mkMaintenancePackage {
        inherit pkgs maintenance;
        commandPath = [ "check" ];
        outputName = "phenix-source-maintenance";
      };
      testMaintenancePackage = maintenanceLib.mkMaintenancePackage {
        inherit pkgs maintenance;
        commandPath = [ "test" ];
        outputName = "phenix-test-maintenance";
      };
    in
    {
      packages = {
        phenix-maintenance = maintenancePackage.package;
        phenix-source-maintenance = sourceMaintenancePackage.package;
        phenix-test-maintenance = testMaintenancePackage.package;
      };
      apps = {
        phenix-maintenance = maintenancePackage.app;
        phenix-source-maintenance = sourceMaintenancePackage.app;
        phenix-test-maintenance = testMaintenancePackage.app;
      };

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
