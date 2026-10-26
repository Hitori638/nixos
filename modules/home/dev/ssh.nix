{...}: {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."github.com" = {
      hostname = "github.com";
      user = "git";
      identityFile = "~/.ssh/id_ed25519";
    };
    settings."pi5" = {
      hostname = "raspberrypi.local";
      user = "alpha";
    };
  };
}
