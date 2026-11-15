# Redis's rows of the Workload dashboard, shown for its namespace. Unlike other modules' grafana.nix this one doesn't
# import homelab-monitoring's Grafana module: that module imports this flake's PostgreSQL module, so the two would
# import each other, which makes the module system recurse while it collects the imports (as Alloy's and
# Grafana's modules did). The rows are added only where Grafana's options are declared
{ inputs, ... }:
{
  config,
  lib,
  options,
  ...
}:
let
  g = inputs.homelab-monitoring.lib.grafana;
  cfg = config.homelab.redis;
  j = ''namespace="redis"'';
  hasGrafana = options ? homelab && options.homelab ? grafana;
in
{
  options.homelab.redis.grafana.enable = lib.mkOption {
    description = "Whether the Workload dashboard has Redis's rows.";
    type = lib.types.bool;
    default =
      hasGrafana
      && cfg.enable
      && cfg.metrics.enable
      && config.homelab.alloy.enable
      && config.homelab.grafana.enable;
    defaultText = lib.literalExpression ''
      config.homelab.redis.enable && config.homelab.redis.metrics.enable && config.homelab.alloy.enable
      && config.homelab.grafana.enable, where homelab-monitoring's Grafana module is imported
    '';
  };
  config = lib.optionalAttrs hasGrafana {
    homelab.grafana.drilldown.rows.redis = lib.mkIf cfg.grafana.enable {
      workload = "redis";
      row = g.row { title = "Redis"; } (
        g.autoGrid { columns = 3; } [
          (g.stat {
            title = "Clients";
            decimals = 0;
            queries = [ (g.prom "redis_connected_clients{${j}}" { instant = true; }) ];
          })
          (g.stat {
            title = "Memory";
            unit = "bytes";
            queries = [ (g.prom "redis_memory_used_bytes{${j}}" { instant = true; }) ];
          })
          (g.bargauge {
            title = "Keys";
            decimals = 0;
            queries = [
              (g.prom "redis_db_keys{${j}} > 0" {
                instant = true;
                legend = "{{db}}";
              })
            ];
            description = "Each database that has keys";
          })
          (g.timeseries {
            title = "Commands";
            unit = "ops";
            queries = [
              (g.prom "sum(rate(redis_commands_processed_total{${j}}[$__rate_interval]))" {
                legend = "commands";
              })
            ];
          })
          (g.timeseries {
            title = "Key lookups";
            unit = "ops";
            queries = [
              (g.prom "sum(rate(redis_keyspace_hits_total{${j}}[$__rate_interval]))" { legend = "hits"; })
              (g.prom "sum(rate(redis_keyspace_misses_total{${j}}[$__rate_interval]))" { legend = "misses"; })
            ];
          })
          (g.timeseries {
            title = "Memory over time";
            unit = "bytes";
            queries = [ (g.prom "redis_memory_used_bytes{${j}}" { legend = "used"; }) ];
          })
        ]
      );
    };
  };
}
