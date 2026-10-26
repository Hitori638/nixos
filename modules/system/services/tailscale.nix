{...}: {
  services.tailscale.enable = true;

  # Let anything arriving over Tailscale reach Jellyfin (8096) and friends
  networking.firewall.trustedInterfaces = ["tailscale0"];
}
