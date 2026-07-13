{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      devShells.default = pkgs.mkShell {
        name = "phenix-nvim-dev";
        packages = with pkgs; [
          nix
          nixfmt
          statix
          deadnix
          inputs.phenix-tend.packages.${system}.tend
        ];
        shellHook = ''
          _phenix_tend() {
            local profile="$1"
            shift
            tend check --profile "$profile" "$@"
          }
          repo-hook() { _phenix_tend git-hook --staged "$@"; }
          repo-pushgate() { _phenix_tend pre-push "$@"; }
          repo-check() { _phenix_tend manual "$@"; }
          repo-fix() { _phenix_tend fix "$@"; }
          export -f _phenix_tend repo-hook repo-pushgate repo-check repo-fix 2>/dev/null || true

          echo "phenix-nvim dev shell"
          echo "  repo-hook      -> tend check --profile git-hook --staged"
          echo "  repo-pushgate  -> tend check --profile pre-push"
          echo "  repo-check     -> tend check --profile manual"
          echo "  repo-fix       -> tend check --profile fix"
        '';
      };
    };
}
