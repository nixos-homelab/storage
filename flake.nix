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
      inputs.homelab-monitoring.follows = "homelab-monitoring";
    };
    homelab-monitoring = {
      url = "github:nixos-homelab/monitoring";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.kube-generators.follows = "kube-generators";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.homelab-storage.follows = "";
      inputs.docs.follows = "docs";
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
            local-path = importApply ./nix/modules/local-path { inherit self inputs; };
            nfs-provisioner = importApply ./nix/modules/nfs-provisioner { inherit self inputs; };
            postgresql = importApply ./nix/modules/postgresql { inherit self inputs; };
            redis = importApply ./nix/modules/redis { inherit self inputs; };
            smb = importApply ./nix/modules/smb { inherit self inputs; };
          };
        };
        perSystem =
          {
            config,
            pkgs,
            lib,
            ...
          }:
          {
            # One lock node per homelab repo
            checks.flake-lock = inputs.homelab-shared.lib.checks.flakeLock {
              inherit pkgs;
              lockFile = ./flake.lock;
            };
            # Dead Nix code. Pattern names stay: modules take { config, lib, pkgs, ... } whether they use them or not
            checks.deadnix = pkgs.runCommand "deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
              deadnix --fail --no-lambda-pattern-names ${self}
              touch $out
            '';
            # The PromQL of this flake's alert rules through promtool, with Grafana on to have them
            checks.promql = inputs.homelab-monitoring.lib.alerts.check {
              inherit pkgs;
              config =
                (inputs.nixpkgs.lib.nixosSystem {
                  modules =
                    lib.attrValues inputs.homelab-shared.nixosModules
                    ++ lib.attrValues self.nixosModules
                    ++ [
                      inputs.homelab-monitoring.nixosModules.grafana
                      ./nix/tests/config.nix
                    ]
                    ++ [
                      inputs.homelab-shared.lib.checks.fixture
                      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
                      {
                        homelab.alloy.enable = true;
                        homelab.grafana.enable = true;
                      }
                    ];
                }).config;
            };
            checks.manifests = inputs.homelab-shared.lib.checks.manifests {
              inherit pkgs;
              modules = lib.attrValues self.nixosModules ++ [
                ./nix/tests/config.nix
                {
                  # Evaluates the metrics parts of the modules, off with Alloy
                  homelab.alloy.enable = true;
                }
              ];
            };
            # The parsers of this flake's workloads on their examples, through the pinned Alloy and Loki
            checks.logs = inputs.homelab-monitoring.lib.logs.check {
              inherit pkgs;
              modules = lib.attrValues self.nixosModules ++ [ ./nix/tests/config.nix ];
            };
            # The VM tests, under the NixOS test driver (needs KVM): `nix build .#nixosTests.<name>`. They stay out of the
            # checks, so a plain `nix flake check` takes minutes; CI runs both
            # nfs-provisioner and postgresql on one node on k3s' bundled network
            legacyPackages.nixosTests.storage = import ./nix/tests/storage.nix { inherit self inputs pkgs; };
            # That the VM tests evaluate, without building or running them
            checks.nixos-tests = pkgs.writeText "nixos-tests" (
              lib.concatMapStringsSep "\n" (test: builtins.unsafeDiscardOutputDependency test.drvPath) (
                lib.attrValues config.legacyPackages.nixosTests
              )
            );
            packages = {
              options-docs = inputs.docs.lib.docs.options {
                inherit pkgs;
                modules = lib.attrValues self.nixosModules;
                repoPath = toString self;
                repoLinkPrefix = "https://github.com/nixos-homelab/storage/blob/main";
                prefixGroups = {
                  local-path = [ "homelab.local-path" ];
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
