# jellyfin-plugins-nix

This is a Nix flake that allows you to install Jellyfin plugins on NixOS.

## Using the flake

Simply add this flake to your NixOS flake inputs:

```
jellyfin-plugins.url = "github:LoCrealloc/jellyfin-plugins-nix";
```

This flake exposes a NixOS module that allows you to easily add the plugins to your jellyfin instance. If you want to use this module, add the module to your flake modules:

```
modules = [
  ...
  jellyfin-plugins.nixosModules.jellyfin-plugins
  ...
]
```

To add a plugin to your instance, use the exposed configuration option:

```
services.jellyfin.enabledPlugins = { inherit (jellyfin-plugins.packages."x86_64-linux") SSO-Auth; };
```

## Adding a plugin

To add a plugin to this flake, simply create a fork, add a new input to the flake.nix file and add some metadata to the plugins.nix file. Test your changes, commit them and create a pull request.
