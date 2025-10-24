{ pkgs, lib, config, inputs, ... }: let
  pkgs-unstable = import inputs.unstable { system = pkgs.stdenv.system; };
in {
  languages.zig.enable = true;
  languages.zig.package = pkgs-unstable.zigPackages."0.15";
  languages.zig.zls.package = pkgs-unstable.zigPackages."0.15";
}
