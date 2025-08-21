{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    iguana.url = "github:mookums/iguana";
  };

  outputs = inputs@{ nixpkgs, flake-utils, iguana, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (iguana.lib.${system}.mkZigOverlay "mach-latest")
            (iguana.lib.${system}.mkZlsOverlay "mach-latest")
          ];
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ zig zls ];
        };
      }
    );
}
