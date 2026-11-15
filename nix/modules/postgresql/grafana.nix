# PostgreSQL's rows of the Workload dashboard, shown for its namespace. Unlike other modules' grafana.nix this one doesn't
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
  cfg = config.homelab.postgresql;
  j = ''namespace="postgresql"'';
  hasGrafana = options ? homelab && options.homelab ? grafana;
in
{
  options.homelab.postgresql.grafana.enable = lib.mkOption {
    description = "Whether the Workload dashboard has PostgreSQL's rows.";
    type = lib.types.bool;
    default =
      hasGrafana
      && cfg.enable
      && cfg.metrics.enable
      && config.homelab.alloy.enable
      && config.homelab.grafana.enable;
    defaultText = lib.literalExpression ''
      config.homelab.postgresql.enable && config.homelab.postgresql.metrics.enable && config.homelab.alloy.enable
      && config.homelab.grafana.enable, where homelab-monitoring's Grafana module is imported
    '';
  };
  config = lib.optionalAttrs hasGrafana {
    homelab.grafana.drilldown.rows.postgresql = lib.mkIf cfg.grafana.enable {
      workload = "postgresql";
      row = g.row { title = "PostgreSQL"; } (
        g.autoGrid { columns = 2; } [
          (g.bargauge {
            title = "Database size";
            unit = "bytes";
            queries = [
              (g.prom "sort_desc(pg_database_size_bytes{${j}})" {
                instant = true;
                legend = "{{datname}}";
              })
            ];
          })
          (g.timeseries {
            title = "Database size over time";
            unit = "bytes";
            queries = [ (g.prom "pg_database_size_bytes{${j}}" { legend = "{{datname}}"; }) ];
          })
          (g.timeseries {
            title = "Locks";
            decimals = 0;
            queries = [ (g.prom "sum by (mode) (pg_locks_count{${j}})" { legend = "{{mode}}"; }) ];
          })
        ]
      );
    };
  };
}
