# postgres_exporter as a sidecar of PostgreSQL, logging in as a role with pg_monitor alone
{ inputs, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.homelab.postgresql;
  role = "metrics";
  port = 9187;
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/postgres-exporter";
    config.Entrypoint = [ (lib.getExe pkgs.prometheus-postgres-exporter) ];
  };
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        homelab.alloy.monitors.postgresql.podPort = port;
        assertions = [
          {
            assertion = lib.all (spec: spec.username != role) (lib.attrValues cfg.databases);
            message = "homelab.postgresql.databases has the username ${role}, the role of the metrics exporter";
          }
        ];
      }
      (lib.mkIf config.homelab.alloy.enable {
        homelab.cluster.images = [ image ];
        homelab.postgresql.startupSql = ''
          SELECT 'CREATE ROLE ${role} LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${role}')\gexec
          GRANT pg_monitor TO ${role}
        '';
        homelab.kubernetes.submodules.instances.postgresql.config.submodules.instances.postgresql.config.kubernetes.resources = {
          services.postgresql.spec.ports.metrics.port = port;
          deployments.postgresql.spec.template = {
            metadata.annotations."kubectl.kubernetes.io/default-container" = "postgresql";
            # Over TCP to localhost, which pg_hba.conf from initdb trusts: no password to hold. The exporter shares the
            # pod's network namespace, so the trust is what it had anyway; the role keeps it to pg_monitor
            spec.containers.metrics = {
              image = "${image.buildArgs.name}:${image.imageTag}";
              imagePullPolicy = "Never";
              env = {
                DATA_SOURCE_URI.value = "localhost:5432/postgres?sslmode=disable";
                DATA_SOURCE_USER.value = role;
              };
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
