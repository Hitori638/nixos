{pkgs, ...}: {
  home.packages = with pkgs; [
    nodejs
    gcc
    cargo
    rustc
    rustfmt
    clippy
    rust-analyzer
  ];

  home.sessionVariables = {
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };
}
