{ inputs, self, ... }:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.homelab.local-path;
  hllib = inputs.homelab-shared.lib;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
  src = pkgs.fetchFromGitHub {
    owner = "rancher";
    repo = "local-path-provisioner";
    rev = "v0.0.37";
    hash = "sha256-H/YuDKAXmh8TpkSuIo/v1v12mxmO2qWOCB638PSdLEs=";
  };
  provisioner = pkgs.buildGo126Module {
    pname = "local-path-provisioner";
    version = lib.removePrefix "v" src.rev;
    inherit src;
    # Upstream vendors its modules
    vendorHash = null;
    env.CGO_ENABLED = 0;
    meta.mainProgram = "local-path-provisioner";
  };
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/local-path-provisioner";
    copyToRoot = [ provisioner ];
    config.Entrypoint = [ (lib.getExe provisioner) ];
  };
  # The pod that creates and removes a volume's directory runs the chart's setup and teardown scripts with sh
  helper = pkgs.dockerTools.buildImage {
    name = "cluster.local/local-path-helper";
    copyToRoot = [ pkgs.busybox ];
    config.Entrypoint = [ "/bin/sh" ];
  };
in
{
  key = "${toString __curPos.file}#modules.nixos.local-path";
  imports = self.lib.importsApply [
    ./grafana.nix
    ./logs.nix
  ];
  options.homelab.local-path = {
    enable = lib.mkEnableOption "the local volume provisioner, volumes as directories on the node";
    path = lib.mkOption {
      description = "Directory on the node the volumes are created in";
      type = lib.types.str;
      default = "/var/lib/local-path";
    };
    pathPattern = lib.mkOption {
      description = ''
        Naming scheme for volumes below the path, a Go template on the PVC. The provisioner refuses one that doesn't start
        with `{{ .PVC.Namespace }}/{{ .PVC.Name }}/`.
      '';
      type = lib.types.str;
      default = "{{ .PVC.Namespace }}/{{ .PVC.Name }}/";
    };
    defaultClass = lib.mkOption {
      description = ''
        Whether `local-path` is the default StorageClass, which the workloads' volume claims get, as they name none.
        Only one provisioner can be the default.
      '';
      type = lib.types.bool;
      default = true;
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          !(
            cfg.defaultClass
            && config.homelab.nfs-provisioner.enable
            && config.homelab.nfs-provisioner.defaultClass
          );
        message = "homelab.local-path and homelab.nfs-provisioner are both the default StorageClass; set defaultClass = false on one.";
      }
    ];
    systemd.tmpfiles.rules = [ "d ${cfg.path} 0755 root root -" ];
    homelab.cluster.images = [
      image
      helper
    ];
    homelab.cluster.manifests.local-path.source =
      hllib.k8s.patchManifest { inherit pkgs; }
        (pkgs.runCommand "local-path.yaml" {
          # The namespace in the same manifest as the chart, so the chart's objects land in the deploy controller's first pass
          namespace = kubelib.toYAMLStreamFile [
            {
              apiVersion = "v1";
              kind = "Namespace";
              metadata.name = "local-path";
            }
          ];
          chart = kubelib.buildHelmChart {
            name = "local-path-provisioner";
            namespace = "local-path";
            chart = "${src}/deploy/chart/local-path-provisioner";
            values = {
              image = {
                repository = image.buildArgs.name;
                tag = image.imageTag;
              };
              helperImage = {
                repository = helper.buildArgs.name;
                tag = helper.imageTag;
              };
              storageClass = {
                inherit (cfg) defaultClass pathPattern;
                name = "local-path";
                reclaimPolicy = "Retain";
              };
              nodePathMap = [
                {
                  node = "DEFAULT_PATH_FOR_NON_LISTED_NODES";
                  paths = [ cfg.path ];
                }
              ];
            };
          };
        } ''cat "$namespace" - "$chart" <<<--- >"$out"'')
        (
          # The provisioner watches claims through the API server
          kubelib.toYAMLStreamFile [
            {
              apiVersion = "apps/v1";
              kind = "Deployment";
              metadata.namespace = "local-path";
              metadata.name = "local-path-provisioner";
              spec.template.metadata.labels."cluster.local/apiserver-egress" = "allow";
            }
          ]
        );
  };
}
