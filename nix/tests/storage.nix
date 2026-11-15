# The storage modules on one node with k3s' bundled network (no networking modules), as the manifests check configures
# them, under the NixOS test driver. The node serves the NFS export nfs-provisioner mounts, as the NAS does
{
  self,
  inputs,
  pkgs,
}:
pkgs.testers.runNixOSTest {
  name = "storage";
  nodes.node =
    { config, lib, ... }:
    {
      imports =
        lib.attrValues inputs.homelab-shared.nixosModules
        ++ lib.attrValues self.nixosModules
        ++ [
          inputs.homelab-shared.lib.checks.fixture
          ./config.nix
        ];
      networking.hostName = lib.mkForce "node";
      homelab.k3s = {
        bundledNetworking = true;
        dataDir = lib.mkForce "/var/lib/k3s";
      };
      # On a real machine these are filesystems of their own, which exist before k3s and the NFS server start
      systemd.tmpfiles.rules = [
        "d /var/lib/k3s 0700 root root -"
        "d /srv/nfs 0750 900 900 -"
      ];
      # The pods run as the owner of the volumes nfs-provisioner makes, as on the NAS
      homelab.nfs-provisioner.mountpointOwnership = {
        uid = 900;
        gid = 900;
      };
      homelab.workloads.securityContext = {
        runAsUser = 900;
        runAsGroup = 900;
      };
      # The CLI the test runs in place of the activation and service a real machine has
      environment.systemPackages = [ config.setup-secrets.script ];
      # The node mounts its own export through the FQDN nfs-provisioner defaults to, which points at loopback
      networking.hosts."127.0.0.2" = [ "node.${config.homelab.workloads.domain}" ];
      services.nfs.server = {
        enable = true;
        exports = "/srv/nfs 127.0.0.0/8(rw,root_squash,anonuid=900,anongid=900)\n";
      };
      # k3s waits for a default route; the test network has none
      networking.defaultGateway = {
        address = "192.168.1.254";
        interface = "eth1";
      };
      virtualisation = {
        memorySize = 4096;
        cores = 2;
        diskSize = 8192;
      };
    };
  testScript = builtins.readFile ./storage.py;
}
