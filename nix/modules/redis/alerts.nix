# Redis's alert rule: the server down
{ inputs, ... }:
{ config, lib, ... }:
let
  g = inputs.homelab-monitoring.lib.grafana;
  cfg = config.homelab.redis;
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.grafana ];
  options.homelab.redis.alerts.enable = lib.mkOption {
    description = "Whether Grafana alerts on Redis being down.";
    type = lib.types.bool;
    default =
      cfg.enable
      && cfg.metrics.enable
      && config.homelab.alloy.enable
      && config.homelab.grafana.alerting.enable;
    defaultText = lib.literalExpression ''
      config.homelab.redis.enable && config.homelab.redis.metrics.enable && config.homelab.alloy.enable
      && config.homelab.grafana.alerting.enable
    '';
  };
  config = lib.mkIf cfg.alerts.enable {
    homelab.grafana.alerting.groups.redis.rules.down = g.alert {
      title = "Redis down";
      query = ''min(redis_up{namespace="redis"})'';
      below = 1;
      for = "5m";
      severity = "warning";
      summary = "redis_exporter can't reach Redis";
      dashboardUid = "workload";
    };
  };
}
