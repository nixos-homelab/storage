{ inputs, ... }:
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.homelab.redis;
  image = (inputs.homelab-shared.lib.images.pinned pkgs ./Dockerfile).redis;
  exporterImage = pkgs.dockerTools.buildImage {
    name = "cluster.local/redis-exporter";
    config.Entrypoint = [ (lib.getExe pkgs.prometheus-redis-exporter) ];
  };
in
{
  key = "${toString __curPos.file}#modules.nixos.redis";
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  options.homelab.redis = {
    enable = lib.mkEnableOption "Redis";
    databases = lib.mkOption {
      description = "A map of symbolic names to redis db indices. Overlaps will cause an assertion failure.";
      type = lib.types.attrsOf lib.types.str;
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = with builtins; [
      (
        let
          overlaps = lib.filterAttrs (_idx: names: length names > 1) (
            lib.zipAttrs (lib.mapAttrsToList (name: value: { ${value} = name; }) cfg.databases)
          );
        in
        {
          assertion = length (attrNames overlaps) == 0;
          message = ''
            homelab.redis.databases has overlaps in db indices.
            ${lib.join "\n" (
              lib.mapAttrsToList (idx: names: "The index ${idx} is used by: ${lib.join ", " names}") overlaps
            )}
          '';
        }
      )
      (
        let
          nonInts = lib.filterAttrs (_name: idx: toString (lib.toIntBase10 idx) != idx) cfg.databases;
        in
        {
          assertion = length (attrNames nonInts) == 0;
          message = ''
            homelab.redis.databases contains non-integer strings as db indices.
            ${lib.join "\n" (
              lib.mapAttrsToList (name: idx: ''The index "${idx}" used by "${name}" is not valid.'') nonInts
            )}
          '';
        }
      )
    ];
    homelab.cluster.images = [
      image
      exporterImage
    ];
    homelab.alloy.monitors.redis = { };
    homelab.cluster.backup.volumes.redis.redis = [ "/dump.rdb" ];
    homelab.kubernetes.submodules.instances.redis = {
      submodule = "workload";
      args = {
        dataPath = "/data";
        ports = {
          redis = 6379;
          metrics = 9121;
        };
        container = {
          image = image.ref;
          imagePullPolicy = "Never";
          livenessProbe.tcpSocket.port = "redis";
          readinessProbe.tcpSocket.port = "redis";
        };
      };
      config.kubernetes.resources.deployments.redis.spec.template = {
        metadata.annotations."kubectl.kubernetes.io/default-container" = "redis";
        # The port is the exporter's, which listens in the pod beside redis
        spec.containers.redis.ports = lib.mkForce { redis.containerPort = 6379; };
        # Redis runs without a password, and the exporter's default address is localhost:6379
        spec.containers.metrics = {
          image = "${exporterImage.buildArgs.name}:${exporterImage.imageTag}";
          imagePullPolicy = "Never";
          ports.metrics.containerPort = 9121;
          livenessProbe.httpGet.port = "metrics";
          readinessProbe.httpGet.port = "metrics";
          securityContext = {
            allowPrivilegeEscalation = false;
            readOnlyRootFilesystem = true;
            capabilities.drop = [ "ALL" ];
          };
        };
      };
    };
  };
}
