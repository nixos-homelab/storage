# The storage modules as the checks set them up: nfs-provisioner on /srv/nfs, postgresql with two databases of one
# consumer (the second with a hyphen in its name, the first backed up), redis
{
  homelab = {
    nfs-provisioner = {
      enable = true;
      path = "/srv/nfs";
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
