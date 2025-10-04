{
  description = "Nix devenv";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        buildInputs = with pkgs; [
          pkg-config
          zig_0_15
          zls_0_15
          sdl3
          libGL
          vulkan-loader
          wayland
          libxkbcommon
          libdecor
          xorg.libX11
          xorg.libXcursor
          xorg.libXrandr
          xorg.libXi
          # for compression
          oxipng
          ktx-tools
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          inherit buildInputs;
          # headers for translate-c
          CPATH = pkgs.lib.makeSearchPathOutput "dev" "include" buildInputs;
          PKG_CONFIG_PATH = pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" buildInputs;
          # runtime libs
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;
          DYLD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;
        };
      }
    );
}


