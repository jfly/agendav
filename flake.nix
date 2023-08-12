{
  description = "AgenDAV - A CalDAV web client similar to Google Calendar";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [];
      systems = [ "x86_64-linux" ];
      flake = {};
      perSystem = { config, self', inputs', pkgs, system, ... }:
        let
          agendav = pkgs.callPackage ./agendav.nix {};
        in
        {
          packages.default = agendav.all;
        };
    };
}
