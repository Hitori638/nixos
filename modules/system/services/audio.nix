{...}: {
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  services.pipewire.wireplumber.extraConfig."99-bluetooth-default" = {
    "monitor.bluez.rules" = [
      {
        matches = [{"device.name" = "~bluez_card.*";}];
        actions = {
          update-props = {
            "priority.session" = 2000;
          };
        };
      }
    ];
  };
  services.pipewire.wireplumber.extraConfig."51-chu2-soft-volume" = {
    "monitor.alsa.rules" = [
      {
        matches = [{"device.name" = "~alsa_card.usb-KTMicro_Chu2.*";}];
        actions.update-props = {
          "api.alsa.soft-mixer" = true;
        };
      }
    ];
  };
}
