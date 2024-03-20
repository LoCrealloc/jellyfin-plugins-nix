{
  description = "A flake that makes managing 3rd party Jellyfin plugins with Nix easy";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    alejandra = {
      url = "github:kamadorueda/alejandra/3.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    "SSO-Auth" = {
      url = "file+https://github.com/9p4/jellyfin-plugin-sso/releases/download/v3.5.2.3/sso-authentication_3.5.2.3.zip";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    alejandra,
    ...
  } @ inputs: let
    lib = nixpkgs.lib;
    plugins = import ./plugins.nix;

    defaultSystems = [
      "x86_64-darwin"
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];

    eachDefaultSystem = lib.genAttrs defaultSystems;
  in {
    formatter.x86_64-linux = alejandra.defaultPackage."x86_64-linux";

    packages = eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
    in (
      builtins.mapAttrs
      (name: value:
        pkgs.stdenvNoCC.mkDerivation {
          src = value;
          pname = name;
          version = plugins."${name}".version;
          nativeBuildInputs = with pkgs; [unzip];
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
    nixosModules.jellyfin-plugins = {
      config,
      pkgs,
      ...
    }: {
      options.services.jellyfin-plugins = {
        configs =
          builtins.mapAttrs
          (name: _: {
            settings = lib.mkOption {
              description = "The config for the plugin in XML";
              type = lib.types.nullOr lib.types.str;
              default = null;
            };

            path = lib.mkOption {
              description = "A path to a XML configuration file; useful if you need to provide secrets to the plugin";
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
          })
          self.packages."${builtins.elemAt defaultSystems 0}";
        enabledPlugins = lib.mkOption {
          type = lib.types.attrsOf lib.types.package;
          default = {};
        };
      };

      config = let
        cfg = config.services.jellyfin-plugins;

        configurations = pkgs.linkFarm "plugin-configurations" (lib.attrsets.mapAttrsToList
          (name: config: {
            name = "${name}.xml";

            path =
              if config.settings != null
              then
                (builtins.toFile name ''
                  <?xml version="1.0" encoding="utf-8"?>
                  <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                  	${config.settings}
                  </PluginConfiguration>
                '')
              else config.path;
          })
          (lib.attrsets.filterAttrs (n: config: ((config.settings != null) || (config.path != null))) cfg.configs));
      in
        lib.mkIf config.services.jellyfin.enable {
          assertions =
            lib.attrsets.mapAttrsToList (name: config: {
              assertion = (config.settings == null) || (config.path == null);
              message = "Only one of settings or path may be used for plugin configuration";
            })
            cfg.configs;

          systemd.services.jellyfin.preStart =
            ''
              #mv /var/lib/jellyfin/plugins /var/lib/jellyfin/plugins.orig
              #mkdir -p /var/lib/jellyfin/plugins
              #ln -s ${configurations} /var/lib/jellyfin/plugins/configurations
            ''
            + (
              lib.strings.concatMapStrings
              (
                plugin: ''
                  mkdir -p /var/lib/jellyfin/plugins/${plugin.name}
                  cp ${plugin.path}/* /var/lib/jellyfin/plugins/${plugin.name}/.
                  chmod -R 770 /var/lib/jellyfin/plugins/${plugin.name}
                ''
              )
              (lib.attrsets.mapAttrsToList (name: path: {inherit name path;}) cfg.enabledPlugins)
            );
          systemd.services.jellyfin.postStop = ''
            rm -rf /var/lib/jellyfin/plugins
            #mv -T /var/lib/jellyfin/plugins.orig /var/lib/jellyfin/plugins
          '';
        };
    };
  };
}
