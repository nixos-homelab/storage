# How the local volume provisioner's logs are parsed
{ inputs, ... }:
{
  lib,
  config,
  ...
}:
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  config = lib.mkIf config.homelab.local-path.enable {
    homelab.alloy.logs.pods.local-path-provisioner = {
      namespace = "local-path";
      # logrus' logfmt from the provisioner, klog from its controller library
      format = "go";
      examples = [
        {
          lines = [
            ''time="2026-11-26T07:41:02Z" level=info msg="Creating volume pvc-0d5e0c1b-3a4f-4f8e-9a51-6c2b1f0e7d42 at desktop:/var/lib/local-path/grafana/grafana/"''
            ''I1126 08:01:55.519036       1 controller.go:887] "Started provisioner controller"''
          ];
          expect = [
            {
              message = "Creating volume pvc-0d5e0c1b-3a4f-4f8e-9a51-6c2b1f0e7d42 at desktop:/var/lib/local-path/grafana/grafana/";
              level = "info";
            }
            {
              message = "Started provisioner controller";
              level = "info";
              fields.caller = "controller.go:887";
            }
          ];
        }
      ];
    };
  };
}
