# PostgreSQL's row of the Workload dashboard, shown for its namespace. Unlike other modules' grafana.nix this one doesn't
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
        g.pack [
          {
            w = 6;
            h = 4;
            panel = g.stat {
              title = "Connections";
              description = "Connections open, of max_connections: past it new clients are refused. Orange from 70 %, red from 90 %";
              unit = "percentunit";
              levels = g.levels {
                warn = 0.7;
                crit = 0.9;
              };
              queries = [
                (g.prom "sum(pg_stat_database_numbackends{${j}}) / max(pg_settings_max_connections{${j}})" { })
              ];
            };
          }
          {
            w = 6;
            h = 4;
            panel = g.stat {
              title = "Cache hits";
              description = "The share of block reads PostgreSQL's shared buffers answered without the disk; under 95 % (orange) the working set doesn't fit, under 90 % (red) queries wait on I/O";
              unit = "percentunit";
              levels = g.levels {
                warn = 0.95;
                crit = 0.9;
                below = true;
              };
              queries = [
                (g.prom
                  "sum(rate(pg_stat_database_blks_hit{${j}}[$__rate_interval])) / (sum(rate(pg_stat_database_blks_hit{${j}}[$__rate_interval])) + sum(rate(pg_stat_database_blks_read{${j}}[$__rate_interval])))"
                  { }
                )
              ];
            };
          }
          {
            w = 6;
            h = 4;
            panel = g.stat {
              title = "Rollbacks";
              description = "The share of transactions rolled back rather than committed, in the hour before: an app's failing writes. Orange from 5 %, red from 20 %";
              unit = "percentunit";
              levels = g.levels {
                warn = 0.05;
                crit = 0.2;
              };
              queries = [
                (g.prom
                  "sum(increase(pg_stat_database_xact_rollback{${j}}[1h])) / (sum(increase(pg_stat_database_xact_commit{${j}}[1h])) + sum(increase(pg_stat_database_xact_rollback{${j}}[1h])))"
                  { }
                )
              ];
            };
          }
          {
            w = 6;
            h = 4;
            panel = g.stat {
              title = "Deadlocks";
              description = "Deadlocks PostgreSQL broke in the hour before by aborting one of the transactions; orange from 1, red from 5";
              decimals = 0;
              levels = g.levels {
                warn = 1;
                crit = 5;
              };
              queries = [ (g.prom "sum(increase(pg_stat_database_deadlocks{${j}}[1h])) or vector(0)" { }) ];
            };
          }
          {
            w = 12;
            h = 8;
            panel = g.timeseries {
              title = "Transactions";
              description = "Commits per database, as stacked bars: which app keeps PostgreSQL busy";
              unit = "ops";
              legend = "right";
              custom = {
                drawStyle = "bars";
                stacking.mode = "normal";
                fillOpacity = 70;
                lineWidth = 0;
              };
              queryOptions.maxDataPoints = 120;
              queries = [
                (g.prom
                  ''sum by (datname) (rate(pg_stat_database_xact_commit{${j}, datname!~"template.*"}[$__rate_interval])) > 0''
                  {
                    legend = "{{datname}}";
                  }
                )
              ];
            };
          }
          {
            w = 12;
            h = 8;
            panel = g.timeseries {
              title = "Rows written";
              description = "Rows inserted, updated and deleted per second, every database together";
              unit = "rowsps";
              custom = {
                stacking.mode = "normal";
                fillOpacity = 40;
              };
              queries = [
                (g.prom "sum(rate(pg_stat_database_tup_inserted{${j}}[$__rate_interval]))" { legend = "inserted"; })
                (g.prom "sum(rate(pg_stat_database_tup_updated{${j}}[$__rate_interval]))" { legend = "updated"; })
                (g.prom "sum(rate(pg_stat_database_tup_deleted{${j}}[$__rate_interval]))" { legend = "deleted"; })
              ];
            };
          }
          {
            w = 8;
            h = 8;
            panel = g.bargauge {
              title = "Database size";
              description = "Each database on disk, the biggest first";
              unit = "bytes";
              min = 0;
              queries = [
                (g.prom ''sort_desc(pg_database_size_bytes{${j}, datname!~"template.*"})'' {
                  instant = true;
                  legend = "{{datname}}";
                })
              ];
            };
          }
          {
            w = 8;
            h = 8;
            panel = g.timeseries {
              title = "Connections by database";
              description = "Each database's open connections over time";
              decimals = 0;
              legend = "right";
              custom = {
                stacking.mode = "normal";
                fillOpacity = 40;
              };
              queries = [
                (g.prom ''sum by (datname) (pg_stat_database_numbackends{${j}, datname!~"template.*"}) > 0'' {
                  legend = "{{datname}}";
                })
              ];
            };
          }
          {
            w = 8;
            h = 8;
            panel = g.timeseries {
              title = "Locks";
              description = "Locks held, by mode: AccessShare is every read, the Exclusive ones block others";
              decimals = 0;
              legend = "right";
              queries = [ (g.prom "sum by (mode) (pg_locks_count{${j}}) > 0" { legend = "{{mode}}"; }) ];
            };
          }
        ]
      );
    };
  };
}
