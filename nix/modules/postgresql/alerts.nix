# PostgreSQL's alert rules: the server down, and a database dump older than 26 hours (from kube-state-metrics, which
# knows when each backup CronJob last succeeded). Like grafana.nix it doesn't import homelab-monitoring's Grafana
# module, which imports this flake's PostgreSQL module: the rules are added only where Grafana's options are declared
{ inputs, ... }:
{
  config,
  lib,
  options,
  ...
}:
let
  g = inputs.homelab-monitoring.lib.grafana;
  cfg = config.homelab.postgresql;
  hasAlerting = options ? homelab && options.homelab ? grafana && options.homelab.grafana ? alerting;
in
{
  options.homelab.postgresql.alerts.enable = lib.mkOption {
    description = "Whether Grafana alerts on PostgreSQL being down and on its backups.";
    type = lib.types.bool;
    default =
      hasAlerting
      && cfg.enable
      && cfg.metrics.enable
      && config.homelab.alloy.enable
      && config.homelab.grafana.alerting.enable;
    defaultText = lib.literalExpression ''
      config.homelab.postgresql.enable && config.homelab.postgresql.metrics.enable && config.homelab.alloy.enable
      && config.homelab.grafana.alerting.enable, where homelab-monitoring's Grafana module is imported
    '';
  };
  config = lib.optionalAttrs hasAlerting {
    homelab.grafana.alerting.groups.postgresql.rules = lib.mkIf cfg.alerts.enable (
      {
        down = g.alert {
          title = "PostgreSQL down";
          query = ''min(pg_up{namespace="postgresql"})'';
          below = 1;
          for = "5m";
          severity = "critical";
          summary = "postgres_exporter can't reach PostgreSQL: every service with a database is down with it";
          dashboardUid = "workload";
        };
      }
      // lib.optionalAttrs (lib.any (spec: spec.backup.enable) (lib.attrValues cfg.databases)) {
        # The dumps run daily by default; a CronJob that never succeeded has no series yet
        backup-old = g.alert {
          title = "PostgreSQL backup old";
          query = ''max by (cronjob) (time() - kube_cronjob_status_last_successful_time{namespace="postgresql", cronjob=~"backup-.+-db"})'';
          above = 26 * 3600;
          for = "15m";
          severity = "warning";
          summary = "{{ $labels.cronjob }} last succeeded {{ humanizeDuration $values.B.Value }} ago";
          dashboardUid = "workload";
        };
      }
    );
  };
}
