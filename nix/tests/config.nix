# The storage modules as the checks set them up: nfs-provisioner on /srv/nfs, local-path beside it, postgresql with two
# databases of one consumer (the second with a hyphen in its name, the first backed up), redis
{
  homelab = {
    nfs-provisioner = {
      enable = true;
      path = "/srv/nfs";
    };
    # Beside it, not the default
    local-path = {
      enable = true;
      defaultClass = false;
    };
    postgresql = {
      enable = true;
      # Two databases of one consumer, the second with a hyphen in its name
      databases = {
        myapp.backup.enable = true;
        myapp-log = {
          namespace = "myapp";
          username = "myapp";
        };
      };
    };
    redis = {
      enable = true;
      databases = { };
    };
  };
}
