# How the NFS provisioner's logs are parsed
{ inputs, ... }:
{
  lib,
  config,
  ...
}:
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  config = lib.mkIf config.homelab.nfs-provisioner.enable {
    homelab.alloy.logs.pods.nfs-subdir-external-provisioner = {
      namespace = "nfs-provisioner";
      format = "klog";
      examples = [
        {
          lines = [
            "I1118 07:20:11.381721       1 controller.go:835] Starting provisioner controller cluster.local/nfs-subdir-external-provisioner_nfs-subdir-external-provisioner-d6686f995-v67pm_335fcf04!"
          ];
          expect = [
            {
              message = "Starting provisioner controller cluster.local/nfs-subdir-external-provisioner_nfs-subdir-external-provisioner-d6686f995-v67pm_335fcf04!";
              level = "info";
              fields.caller = "controller.go:835";
            }
          ];
        }
      ];
    };
  };
}
