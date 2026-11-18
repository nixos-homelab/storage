# How Redis' logs are parsed: pid:role date level-symbol message, the role telling the server from its forks
{ inputs, ... }:
{
  lib,
  config,
  ...
}:
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  config = lib.mkIf config.homelab.redis.enable {
    homelab.alloy.logs = {
      formats.redis = {
        # 1:M 18 Nov 2026 13:17:40.044 * message; the logo at start and other bare lines belong to the record before
        firstline = "^\\d+:[MCSX] \\d+ \\w+ \\d{4} \\d\\d:\\d\\d:\\d\\d\\.\\d+ [.*#-] ";
        stages = ''
          stage.regex {
            expression = "^(?P<pid>\\d+):(?P<role>[MCSX]) \\d+ \\w+ \\d{4} \\d\\d:\\d\\d:\\d\\d\\.\\d+ (?P<level>[.*#-]) (?s)(?P<message>.*)$"
          }
          // M is the server, C a fork saving the dataset or rewriting the AOF, S a replica, X a sentinel
          stage.template {
            source   = "program"
            template = "{{ with index . \"role\" }}{{ if eq . \"C\" }}redis-child{{ else if eq . \"S\" }}redis-replica{{ else if eq . \"X\" }}redis-sentinel{{ else }}redis-server{{ end }}{{ end }}"
          }
        '';
        # server.c: ".-*#" for LL_DEBUG, LL_VERBOSE, LL_NOTICE, LL_WARNING
        levels = {
          debug = [ "." ];
          verbose = [ "-" ];
          info = [ "*" ];
          warning = [ "#" ];
        };
      };
      pods.redis = {
        format = "redis";
        examples = [
          {
            lines = [
              "1:M 18 Nov 2026 13:17:40.044 * 100 changes in 300 seconds. Saving..."
              "89:C 18 Nov 2026 13:17:40.055 * BGSAVE done, 65 keys saved, 0 keys skipped, 1463346 bytes written."
              "1:M 18 Nov 2026 13:20:00.000 # WARNING Memory overcommit must be enabled!"
              "1:M 18 Nov 2026 13:20:00.001 - Accepted 10.42.0.7:51234"
            ];
            expect = [
              {
                message = "100 changes in 300 seconds. Saving...";
                level = "info";
                program = "redis-server";
                fields.pid = "1";
              }
              {
                message = "BGSAVE done, 65 keys saved, 0 keys skipped, 1463346 bytes written.";
                level = "info";
                program = "redis-child";
                fields.pid = "89";
              }
              {
                message = "WARNING Memory overcommit must be enabled!";
                level = "warning";
                program = "redis-server";
              }
              {
                message = "Accepted 10.42.0.7:51234";
                level = "verbose";
              }
            ];
          }
        ];
      };
      # The exporter sidecar of metrics.nix
      pods.redis-metrics = {
        namespace = "redis";
        container = "metrics";
        format = "logfmt";
        examples = [
          {
            lines = [
              ''time="2026-11-18T07:21:29Z" level=info msg="Providing metrics at :9121/metrics"''
            ];
            expect = [
              {
                message = "Providing metrics at :9121/metrics";
                level = "info";
                program = "metrics";
              }
            ];
          }
        ];
      };
    };
  };
}
