# redis_exporter as a sidecar of Redis
{ inputs, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  port = 9121;
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/redis-exporter";
    config.Entrypoint = [ (lib.getExe pkgs.prometheus-redis-exporter) ];
  };
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  config = lib.mkIf config.homelab.redis.enable (
    lib.mkMerge [
      { homelab.alloy.monitors.redis.podPort = port; }
      (lib.mkIf config.homelab.alloy.enable {
        homelab.cluster.images = [ image ];
        homelab.kubernetes.submodules.instances.redis.config.kubernetes.resources = {
          services.redis.spec.ports.metrics.port = port;
          deployments.redis.spec.template = {
            metadata.annotations."kubectl.kubernetes.io/default-container" = "redis";
            # Redis runs without a password, and the exporter's default address is localhost:6379
            spec.containers.metrics = {
              image = "${image.buildArgs.name}:${image.imageTag}";
              imagePullPolicy = "Never";
              ports.metrics.containerPort = port;
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
      })
    ]
  );
}
