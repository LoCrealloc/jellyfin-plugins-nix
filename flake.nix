{
  description = "A flake that allows you to install Jellyfin plugins on NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    "SSO-Auth" = {
      url = "file+https://github.com/9p4/jellyfin-plugin-sso/releases/download/v3.5.2.4/sso-authentication_3.5.2.4.zip";
      flake = false;
    };
    "kodisyncqueue" = {
      url = "file+https://github.com/jellyfin/jellyfin-plugin-kodisyncqueue/releases/download/v11/kodi-sync-queue_11.0.0.0.zip";
      flake = false;
    };
  };

  outputs =
    { self
    , nixpkgs
    , ...
    } @ inputs:
    let
      lib = nixpkgs.lib;
      plugins = import ./plugins.nix;

      # at the moment, I just tested this flake on x86 Linux. If you got different hardware, please test this flake and create a PR!
      defaultSystems = [
        #"x86_64-darwin"
        "x86_64-linux"
        #"aarch64-linux"
        #"aarch64-darwin"
      ];

      eachDefaultSystem = lib.genAttrs defaultSystems;
    in
    {
      formatter."x86_64-linux" = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;

      packages = eachDefaultSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        (
          builtins.mapAttrs
            (name: value:
              pkgs.stdenvNoCC.mkDerivation {
                src = value;
                pname = name;
                nativeBuildInputs = with pkgs; [ unzip ];
                version = plugins."${name}".version;
                unpackPhase = ''
                  unzip ${value}
                '';
                installPhase = ''
                  mkdir -p $out
                  cp -R ./*.dll $out/.
                '';
              })
            (lib.attrsets.getAttrs (lib.attrsets.mapAttrsToList (name: _: name) plugins) inputs)
        ));
      nixosModules.jellyfin-plugins =
        { config
        , pkgs
        , ...
        }: {
          options.services.jellyfin = {
            enabledPlugins = lib.mkOption {
              type = lib.types.attrsOf lib.types.package;
              default = { };
            };
          };
          config =
            let
              cfg = config.services.jellyfin;
            in
            lib.mkIf cfg.enable {
              systemd.services.jellyfin.preStart =
                ''
                  mkdir -p /var/lib/jellyfin/plugins
                ''
                + (
                  lib.strings.concatMapStrings
                    (
                      plugin: ''
                        rm -rf /var/lib/jellyfin/plugins/${plugin.name}
                        mkdir -p /var/lib/jellyfin/plugins/${plugin.name}
                        ln -s ${plugin.path}/* /var/lib/jellyfin/plugins/${plugin.name}/.
                        chmod -R 770 /var/lib/jellyfin/plugins/${plugin.name}
                      ''
                    )
                    (lib.attrsets.mapAttrsToList (name: path: { inherit name path; }) cfg.enabledPlugins)
                );
            };
        };
    };
}
