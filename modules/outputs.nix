{ inputs, ... }:
{
  flake.overlays.default = final: prev: {
    vimPlugins = prev.vimPlugins // {
      phenix-acp = inputs.self.packages.${final.system}.phenix-acp-plugin;
      phenix-ui = inputs.self.packages.${final.system}.phenix-ui-plugin;
      phenix-bars = inputs.self.packages.${final.system}.phenix-bars-plugin;
      phenix-color-preview = inputs.self.packages.${final.system}.phenix-color-preview-plugin;
      phenix-picker = inputs.self.packages.${final.system}.phenix-picker-plugin;
      phenix-session = inputs.self.packages.${final.system}.phenix-session-plugin;
      phenix-theme = inputs.self.packages.${final.system}.phenix-theme-plugin;
      phenix-git = inputs.self.packages.${final.system}.phenix-git-plugin;
      phenix-lsp = inputs.self.packages.${final.system}.phenix-lsp-plugin;
      phenix-completion = inputs.self.packages.${final.system}.phenix-completion-plugin;
      phenix-dashboard = inputs.self.packages.${final.system}.phenix-dashboard-plugin;
      phenix-explorer = inputs.self.packages.${final.system}.phenix-explorer-plugin;
      phenix-terminal = inputs.self.packages.${final.system}.phenix-terminal-plugin;
      phenix-notify = inputs.self.packages.${final.system}.phenix-notify-plugin;
    };
    phenix = (prev.phenix or { }) // {
      nvim-nix = inputs.self.packages.${final.system}.nvim-nix;
    };
  };
}
