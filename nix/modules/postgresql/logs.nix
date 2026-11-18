# How PostgreSQL's logs are parsed. An ERROR and the DETAIL, HINT, CONTEXT, QUERY and STATEMENT lines after it are one
# record, without their repeated prefix
{ inputs, ... }:
{
  lib,
  config,
  ...
}:
let
  prefix = "\\d{4}-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d\\.\\d+ \\w+ \\[\\d+\\] ";
  # The prefix of the continuation lines; a raw string, as Go's string literals know no \d
  stripPrefix = "{{ regexReplaceAll `(?m)^${prefix}` .Value \"\" }}";
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  config = lib.mkIf config.homelab.postgresql.enable {
    homelab.alloy.logs = {
      formats.postgresql = {
        # log_line_prefix '%m [%p] ': 2026-11-18 07:22:10.934 UTC [86] ERROR:  message
        firstline = "^${prefix}(?:LOG|ERROR|FATAL|PANIC|WARNING|NOTICE|INFO|DEBUG\\d):";
        stages = ''
          stage.regex {
            expression = "^\\d{4}-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d\\.\\d+ \\w+ \\[(?P<pid>\\d+)\\] (?P<level>[A-Z]+\\d?):\\s+(?s)(?P<message>.*)$"
          }
          stage.template {
            source   = "message"
            template = ${builtins.toJSON stripPrefix}
          }
        '';
        levels = {
          error = [ "panic" ];
          debug = [
            "debug1"
            "debug2"
            "debug3"
            "debug4"
            "debug5"
          ];
        };
      };
      pods.postgresql = {
        format = "postgresql";
        examples = [
          {
            lines = [
              ''2026-11-18 07:22:10.934 UTC [86] ERROR:  duplicate key value violates unique constraint "cache_data_pkey"''
              "2026-11-18 07:22:10.934 UTC [86] DETAIL:  Key (cache_key)=(authinfo-0-authproxy-admin) already exists."
              "2026-11-18 07:22:10.934 UTC [86] STATEMENT:  INSERT INTO cache_data (cache_key,data,created_at,expires) VALUES($1,$2,$3,$4)"
              "2026-11-18 07:22:12.437 UTC [29] FATAL:  the database system is starting up"
              "2026-11-18 08:05:15.130 UTC [25] LOG:  checkpoint starting: time"
            ];
            expect = [
              {
                message = lib.concatStringsSep "\n" [
                  ''duplicate key value violates unique constraint "cache_data_pkey"''
                  "DETAIL:  Key (cache_key)=(authinfo-0-authproxy-admin) already exists."
                  "STATEMENT:  INSERT INTO cache_data (cache_key,data,created_at,expires) VALUES($1,$2,$3,$4)"
                ];
                level = "error";
                fields.pid = "86";
              }
              {
                message = "the database system is starting up";
                level = "error";
              }
              {
                message = "checkpoint starting: time";
                level = "info";
              }
            ];
          }
        ];
      };
    };
  };
}
