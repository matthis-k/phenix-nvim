{ pkgs, ... }:

let
  nixSources = "find . -type f -name '*.nix' -not -path './.git/*' -not -path './.devenv/*'";
in
{
  scripts = {
    "maintenance-check-format" = {
      packages = [
        pkgs.findutils
        pkgs.nixfmt
      ];
      exec = "${nixSources} -exec nixfmt --check {} +";
    };
    "maintenance-check-statix" = {
      packages = [ pkgs.statix ];
      exec = "statix check --ignore '.git/**'";
    };
    "maintenance-check-deadnix" = {
      packages = [ pkgs.deadnix ];
      exec = "deadnix --fail --no-lambda-arg --no-lambda-pattern-names";
    };
    "maintenance-check-flake" = {
      packages = [
        pkgs.git
        pkgs.nix
      ];
      exec = "nix flake check --accept-flake-config --print-build-logs --keep-going";
    };
    "maintenance-fix-format" = {
      packages = [
        pkgs.findutils
        pkgs.nixfmt
      ];
      exec = "${nixSources} -exec nixfmt {} +";
    };
    "maintenance-fix-statix" = {
      packages = [ pkgs.statix ];
      exec = "statix fix";
    };
    "maintenance-fix-deadnix" = {
      packages = [ pkgs.deadnix ];
      exec = "deadnix --edit --no-lambda-arg --no-lambda-pattern-names";
    };
  };

  tasks = {
    "maintenance:format".exec = "maintenance-check-format";
    "maintenance:statix".exec = "maintenance-check-statix";
    "maintenance:deadnix".exec = "maintenance-check-deadnix";
    "maintenance:flake".exec = "maintenance-check-flake";
    "maintenance:check" = {
      exec = "true";
      after = [
        "maintenance:format"
        "maintenance:statix"
        "maintenance:deadnix"
        "maintenance:flake"
      ];
      before = [ "devenv:enterTest" ];
    };
    "maintenance:fix:format".exec = "maintenance-fix-format";
    "maintenance:fix:statix".exec = "maintenance-fix-statix";
    "maintenance:fix:deadnix".exec = "maintenance-fix-deadnix";
    "maintenance:fix" = {
      exec = "true";
      after = [
        "maintenance:fix:format"
        "maintenance:fix:statix"
        "maintenance:fix:deadnix"
      ];
    };
  };
}
