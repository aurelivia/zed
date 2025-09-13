{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = inputs@{ nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs { inherit system; };

      zig = pkgs.stdenv.mkDerivation rec {
        pname = "zig";
        version = "0.15.1";
        src = pkgs.fetchurl {
          url = "https://ziglang.org/download/${version}/zig-${system}-${version}.tar.xz";
          hash = "sha256-xhxdpu3uoUylHs1eRSDG9Bie9SUDg9sz0BhIKTv6/gU=";
        };
        dontConfigure = true;
        dontBuild = true;
        dontFixup = true;
        installPhase = ''
          mkdir -p $out/{doc,bin,lib}
          [ -d docs ] && cp -r docs/* $out/doc
          [ -d doc ] && cp -r doc/* $out/doc
          cp -r lib/* $out/lib
          cp zig $out/bin/zig
        '';
      };
      zls = pkgs.stdenv.mkDerivation rec {
        pname = "zls";
        version = "0.15.0";
        src = pkgs.fetchurl {
          url = "https://builds.zigtools.org/zls-${system}-${version}.tar.xz";
          hash = "sha256-UIv+P9Y30qAvB/P8faiQA1H0BxFrA2hcXa4mtPAaMN4=";
        };
        sourceRoot = ".";
        dontConfigure = true;
        dontBuild = true;
        dontFixup = true;
        installPhase = ''
          mkdir -p $out/bin
          cp zls $out/bin
        '';
      };
    in {
      devShells.default = pkgs.mkShell {
        packages = [ zig zls ];
      };
    }
  );
}

