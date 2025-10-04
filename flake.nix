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
        spirvOverlay = (
          final: prev: {
            spirv-cross = prev.spirv-cross.overrideAttrs (old: {
              cmakeFlags = (old.cmakeFlags or [ ]) ++ [
                "-DSPIRV_CROSS_ENABLE_C_API=ON"
                "-DSPIRV_CROSS_SHARED=ON"
                "-DBUILD_SHARED_LIBS=ON"
              ];
            });
          }
        );

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ spirvOverlay ];
        };

        sdl3Shadercross = pkgs.stdenv.mkDerivation rec {
          pname = "sdl3-shadercross";
          version = "unstable";
          outputs = [
            "out"
            "dev"
          ];

          src = pkgs.fetchFromGitHub {
            owner = "libsdl-org";
            repo = "SDL_shadercross";
            rev = "main";
            hash = "sha256-Nu++tFFdvJOtqPzlo2c7rHroW5NDS+Gn2G7Oxw9O/Y8=";
          };

          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
          ];
          buildInputs = with pkgs; [
            sdl3
            spirv-cross
            directx-shader-compiler
          ];

          cmakeFlags = [
            "-DBUILD_SHARED_LIBS=ON"
            "-DSDLSHADERCROSS_INSTALL=ON"
            "-DSDLSHADERCROSS_CLI=ON"
            "-DSDLSHADERCROSS_SPIRVCROSS_SHARED=ON"
            "-DSDLSHADERCROSS_VENDORED=OFF"
            "-DSDLSHADERCROSS_TESTS=OFF"
          ];

          postFixup = ''
            moveToOutput "include" "$dev"
            if [ -d "$out/lib/pkgconfig" ]; then
              mkdir -p "$dev/lib"
              mv "$out/lib/pkgconfig" "$dev/lib/"
            fi
            if [ -d "$out/lib/cmake" ]; then
              mkdir -p "$dev/lib"
              mv "$out/lib/cmake" "$dev/lib/"
            fi
          '';
        };

        buildInputs = with pkgs; [
          pkg-config
          zig_0_15
          zls_0_15
          sdl3
          sdl3Shadercross
          libGL
          vulkan-loader
          wayland
          libxkbcommon
          libdecor
          xorg.libX11
          xorg.libXcursor
          xorg.libXrandr
          xorg.libXi
          # compression tools
          oxipng
          ktx-tools
        ];
      in
      {
        packages.default = sdl3Shadercross;
        packages.sdl3Shadercross = sdl3Shadercross;

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
