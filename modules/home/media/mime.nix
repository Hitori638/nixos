{pkgs, ...}: {
  home.packages = with pkgs; [
    foliate
  ];
  xdg.mimeApps = {
    enable = true;
    defaultApplications = let
      imv = ["imv.desktop"];
      evince = ["org.gnome.Evince.desktop"];
      foliate = ["com.github.johnfactotum.Foliate.desktop"];
    in {
      "image/png" = imv;
      "image/jpeg" = imv;
      "image/gif" = imv;
      "image/webp" = imv;
      "image/bmp" = imv;
      "image/tiff" = imv;
      "image/avif" = imv;
      "image/svg+xml" = imv;

      "application/pdf" = evince;
      "application/epub+zip" = foliate;

      # optional: comics
      "application/vnd.comicbook+zip" = evince;
      "application/x-cbz" = evince;
    };
  };
}
