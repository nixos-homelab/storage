# nixos-homelab-storage

Databases and persistent storage on top of [nixos-homelab](https://github.com/nixos-homelab/shared):
the PostgreSQL and Redis instances that apps in the other repos keep
their data in, PersistentVolumes on an NFS export, and Samba file sharing
on the host.

For the full list of module options, see [the documentation](https://nixos-homelab.github.io/storage/), under Options.

## Setup

```nix
{
  inputs = {
    ...
    homelab-storage = {
      url = "github:nixos-homelab/storage";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ...
  };
}
```

```nix
{ inputs, ... }:
{
  imports = [ inputs.homelab-storage.nixosModules.postgresql ];
  config.homelab.postgresql = {
    enable = true;
    databases.myapp.backup.enable = true;
  };
}
```

## Modules

- **postgresql**: a shared PostgreSQL instance with declarative database
  creation and backups.
- **redis**: a shared Redis instance with a database-index registry, to
  keep workloads from colliding on the same DB number.
- **nfs-provisioner**: a dynamic PersistentVolume provisioner backed by
  an NFS export.
- **smb**: Samba file sharing, with per-user passwords set up through
  `setup-secrets`.
