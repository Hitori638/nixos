{pkgs, ...}: {
  home.packages = with pkgs; [
    eza
    yazi
    pywal
    zoxide
    figlet
    upower
    nitch
    alsa-utils
    fastfetch
    brightnessctl
  ];
}
