{pkgs, ...}: {
  home.packages = with pkgs; [
    nil
    biome
    stylua
    neovim
    alejandra
    prettierd
    lua-language-server
    prettier
    arduino-ide
  ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        rust-lang.rust-analyzer
      ];
    };
  };
}
