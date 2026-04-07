{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    vulkan-validation-layers
  ];
  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (
    with pkgs;
    [
      alsa-lib
      libdecor
      libusb1
      libxkbcommon
      vulkan-loader
      wayland
      xorg.libX11
      xorg.libXext
      xorg.libXi
      udev
    ]
  );
}
