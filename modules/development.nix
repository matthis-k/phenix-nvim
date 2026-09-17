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
            description = "Exercise the packaged Neovim distribution and external Phenix AI client";
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
                  "+lua dofile('$repo_root/tests/distribution.lua')" \
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
