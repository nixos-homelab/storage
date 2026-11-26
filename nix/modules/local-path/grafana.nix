# The local-path module's namespace in the `storage` area of the Home dashboard, whose CPU, memory and traffic graphs
# sum the containers by area
{ inputs, ... }:
{ config, lib, ... }:
{
  imports = [ inputs.homelab-monitoring.nixosModules.grafana ];
  config.homelab.grafana.home.areas.storage.namespaces = lib.mkIf config.homelab.local-path.enable [
    "local-path"
  ];
}
