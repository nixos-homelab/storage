# Redis's row of the Workload dashboard, shown for its namespace. Unlike other modules' grafana.nix this one doesn't
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
        g.pack [
          {
            w = 6;
            h = 4;
            panel = g.stat {
              title = "Clients";
              description = "Clients connected to Redis";
              decimals = 0;
              queries = [ (g.prom "sum(redis_connected_clients{${j}})" { }) ];
            };
          }
          {
            w = 6;
            h = 4;
            panel = g.stat {
              title = "Memory";
              description = "The memory Redis's data uses";
              unit = "bytes";
              queries = [ (g.prom "sum(redis_memory_used_bytes{${j}})" { }) ];
            };
          }
          {
            w = 6;
            h = 4;
            panel = g.stat {
              title = "Hit rate";
              description = "The share of key lookups that found their key; a cache under 80 % (orange) or 50 % (red) misses more than it should";
              unit = "percentunit";
              levels = g.levels {
                warn = 0.8;
                crit = 0.5;
                below = true;
              };
              queries = [
                (g.prom
                  "sum(rate(redis_keyspace_hits_total{${j}}[$__rate_interval])) / (sum(rate(redis_keyspace_hits_total{${j}}[$__rate_interval])) + sum(rate(redis_keyspace_misses_total{${j}}[$__rate_interval])))"
                  { }
                )
              ];
            };
          }
          {
            w = 6;
            h = 4;
            panel = g.stat {
              title = "Evicted";
              description = "Keys Redis threw out in the hour before to stay under its memory limit; orange from 1, red from 100";
              decimals = 0;
              levels = g.levels {
                warn = 1;
                crit = 100;
              };
              queries = [ (g.prom "sum(increase(redis_evicted_keys_total{${j}}[1h])) or vector(0)" { }) ];
            };
          }
          {
            w = 12;
            h = 8;
            panel = g.timeseries {
              title = "Lookups";
              description = "Key lookups per second, stacked: hits found their key, misses didn't";
              unit = "ops";
              custom = {
                stacking.mode = "normal";
                fillOpacity = 40;
              };
              queries = [
                (g.prom "sum(rate(redis_keyspace_hits_total{${j}}[$__rate_interval]))" { legend = "hits"; })
                (g.prom "sum(rate(redis_keyspace_misses_total{${j}}[$__rate_interval]))" { legend = "misses"; })
              ];
            };
          }
          {
            w = 12;
            h = 8;
            panel = g.timeseries {
              title = "Memory";
              description = "The memory Redis's data uses, and on the right axis, dashed, its fragmentation: what the allocator holds over what the data needs. Far over 1.5, memory is going to waste";
              unit = "bytes";
              queries = [
                (g.prom "sum(redis_memory_used_bytes{${j}})" { legend = "used"; })
                (g.prom "max(redis_mem_fragmentation_ratio{${j}})" { legend = "fragmentation"; })
              ];
              overrides = [
                {
                  matcher = {
                    id = "byName";
                    options = "fragmentation";
                  };
                  properties = [
                    {
                      id = "unit";
                      value = "none";
                    }
                    {
                      id = "custom.axisPlacement";
                      value = "right";
                    }
                    {
                      id = "custom.lineStyle";
                      value = {
                        fill = "dash";
                        dash = [
                          8
                          6
                        ];
                      };
                    }
                    {
                      id = "custom.fillOpacity";
                      value = 0;
                    }
                  ];
                }
              ];
            };
          }
          {
            w = 8;
            h = 6;
            panel = g.bargauge {
              title = "Keys";
              description = "Keys in each database (each app gets its own number)";
              decimals = 0;
              min = 0;
              queries = [
                (g.prom "redis_db_keys{${j}} > 0" {
                  instant = true;
                  legend = "{{db}}";
                })
              ];
            };
          }
          {
            w = 16;
            h = 6;
            panel = g.timeseries {
              title = "Expired and evicted";
              description = "Keys that ran out their time to live (expired, as meant) and keys thrown out for memory (evicted, a cache too small), as bars";
              decimals = 0;
              custom = {
                drawStyle = "bars";
                stacking.mode = "normal";
                fillOpacity = 70;
                lineWidth = 0;
              };
              queryOptions.maxDataPoints = 120;
              queries = [
                (g.prom "sum(increase(redis_expired_keys_total{${j}}[$__interval]))" { legend = "expired"; })
                (g.prom "sum(increase(redis_evicted_keys_total{${j}}[$__interval]))" { legend = "evicted"; })
              ];
            };
          }
        ]
      );
    };
  };
}
