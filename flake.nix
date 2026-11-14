{
  description = "NixOS Homelab Storage";
  inputs = {
    systems.url = "github:nix-systems/default-linux";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    kube-generators.url = "github:farcaller/nix-kube-generators";
    setup-secrets = {
      url = "github:andsens/nixos-setup-secrets";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    homelab-shared = {
      url = "github:nixos-homelab/shared";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.kube-generators.follows = "kube-generators";
    };
    docs = {
      url = "github:andsens/nix-docs";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
  };
  outputs =
    {
      systems,
      flake-parts,
      nixpkgs,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        flake-parts-lib,
        self,
        inputs,
        lib,
        ...
      }:
      let
        inherit (flake-parts-lib) importApply;
      in
      {
        systems = import systems;
        flake = {
          lib = {
            importsApply = map (path: importApply path { inherit self inputs; });
          };
          nixosModules = {
            nfs-provisioner = importApply ./nix/modules/nfs-provisioner { inherit self inputs; };
            postgresql = importApply ./nix/modules/postgresql { inherit self inputs; };
            redis = importApply ./nix/modules/redis { inherit self inputs; };
            smb = importApply ./nix/modules/smb { inherit self inputs; };
          };
        };
        perSystem =
          { pkgs, lib, ... }:
          {
            checks.manifests = inputs.homelab-shared.lib.checks.manifests {
              inherit pkgs;
              modules = lib.attrValues self.nixosModules ++ [
                {
                  homelab = {
                    nfs-provisioner = {
                      enable = true;
                      path = "/srv/nfs";
                    };
                    postgresql = {
                      enable = true;
                      databases = { };
                    };
                    redis = {
                      enable = true;
                      databases = { };
                    };
                  };
                }
              ];
            };
            packages = {
              options-docs = inputs.docs.lib.docs.options {
                inherit pkgs;
                modules = lib.attrValues self.nixosModules;
                repoPath = toString self;
                repoLinkPrefix = "https://github.com/nixos-homelab/storage/blob/main";
                prefixGroups = {
                  nfs-provisioner = [ "homelab.nfs-provisioner" ];
                  postgresql = [ "homelab.postgresql" ];
                  redis = [ "homelab.redis" ];
                  smb = [ "homelab.smb" ];
                };
              };
              manual-docs = inputs.docs.lib.mkdocs.manual {
                inherit pkgs;
                rootDoc = ./README.md;
              };
            };
          };
      }
    );
}
