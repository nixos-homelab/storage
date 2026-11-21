{ inputs, self, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.postgresql;
  hllib = inputs.homelab-shared.lib;
  # Databases of one consumer share a username
  usernames = lib.unique (
    [ "postgres" ] ++ lib.mapAttrsToList (_serviceName: spec: spec.username) cfg.databases
  );
  usernamesByNamespace = lib.mapAttrs (
    _namespace: specs: lib.unique (map (spec: spec.username) specs)
  ) (lib.groupBy (spec: spec.namespace) (lib.attrValues cfg.databases));
  dbBackups = lib.filterAttrs (_serviceName: spec: spec.backup.enable) cfg.databases;
  passwordSource = username: "POSTGRESQL_PASSWORD_${lib.toUpper username}";
  passwordRef = username: {
    valueFrom.secretKeyRef = {
      name = "${username}-password";
      key = "password";
    };
  };
  entrypoint = pkgs.stdenvNoCC.mkDerivation {
    name = "docker-entrypoint";
    phases = [ "installPhase" ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      cat ${cfg.image.entrypoint} > "$out/bin/docker-entrypoint.sh"
      chmod +x "$out/bin/docker-entrypoint.sh"
      runHook postInstall
    '';
    meta.mainProgram = "docker-entrypoint.sh";
  };
  pgdatadir = "/var/lib/postgresql/${builtins.elemAt (builtins.splitVersion cfg.image.package.version) 0}/docker";
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/postgresql";
    copyToRoot = [
      pkgs.dockerTools.usrBinEnv
      pkgs.bash
      pkgs.coreutils
      pkgs.gosu
      pkgs.glibcLocalesUtf8
      pkgs.findutils
      (cfg.image.package.withPackages (p: (map (e: p.${e}) cfg.image.extensions)))
      entrypoint
    ]
    ++ lib.optionals cfg.debug ccfg.debugTools;
    runAsRoot = ''
      #!${pkgs.runtimeShell}
      ${pkgs.dockerTools.shadowSetup}
      groupadd -r -g ${toString config.homelab.workloads.securityContext.runAsGroup} postgres
      useradd -r -u ${toString config.homelab.workloads.securityContext.runAsUser} -g postgres -d ${pgdatadir} postgres
      mkdir -p /docker-entrypoint-initdb.d
      mkdir -p /etc/postgresql
      mkdir -p /run/postgresql
      mkdir -p /var
      ln -s ../run /var/run
    '';
    config.Env = [
      "PATH=/bin:/usr/bin:/usr/local/bin"
      "PGDATA=${pgdatadir}"
      "LOCALE_ARCHIVE=${pkgs.glibcLocalesUtf8}/lib/locale/locale-archive"
    ];
    config.Entrypoint = [ (lib.getExe entrypoint) ];
    config.Cmd = [ "postgres" ];
    # Fast shutdown: postgres takes SIGTERM as smart shutdown, which waits for every client to disconnect and so for
    # the kill at the end of the grace period. containerd reads the stop signal from the image only; the pod field
    # `lifecycle.stopSignal` is alpha (ContainerStopSignals) at 1.35 and the API server drops it
    config.StopSignal = "SIGINT";
  };
in
{
  key = "${toString __curPos.file}#modules.nixos.postgresql";
  options.homelab.postgresql = {
    enable = lib.mkEnableOption "PostgreSQL";
    debug = lib.mkEnableOption "debug mode";
    dumpsVolume = lib.mkOption {
      description = "Volume source (as specificed on the pod spec) to place database dumps in";
      type = lib.types.attrsOf lib.types.anything;
    };
    databases = lib.mkOption {
      description = "Databases to create and backup, indexed by serviceName";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }@module:
          {
            options = {
              dbName = lib.mkOption {
                description = "Name of the database";
                type = lib.types.nullOr lib.types.str;
                defaultText = "`<serviceName>`";
                default = name;
              };
              username = lib.mkOption {
                description = "Database username";
                type = lib.types.nullOr lib.types.str;
                defaultText = "`<dbName>`";
                default = module.config.dbName;
              };
              namespace = lib.mkOption {
                description = "Namespace of the consumer, which gets the password of `username` as the Secret `postgresql-password`. Databases in one namespace share their username";
                type = lib.types.str;
                defaultText = "`<serviceName>`";
                default = name;
              };
              backup = {
                enable = lib.mkEnableOption "backup of the database";
                schedule = lib.mkOption {
                  description = "Cronjob notation of when the database should be dumped";
                  type = lib.types.nullOr lib.types.str;
                  default = "10 3 * * *";
                  example = "10 3 * * *";
                };
              };
              setupCommands = lib.mkOption {
                description = "Commands to run as a superuser in the database right after it has been created";
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            };
          }
        )
      );
    };
    startupSql = lib.mkOption {
      description = "SQL the postStart hook runs as postgres on every start, after it sets the password of postgres. Each statement ends in `;` (or `\\gexec`): psql runs them as one script with ON_ERROR_STOP.";
      type = lib.types.lines;
      default = "";
      internal = true;
    };
    extraSettings = lib.mkOption {
      description = "Additional postgresql.conf settings";
      type = lib.types.lines;
      default = "";
    };
    image.entrypoint = lib.mkOption {
      description = "The docker-entrypoint to install";
      type = lib.types.package;
      default = pkgs.fetchurl {
        name = "docker-entrypoint.sh";
        url = "https://raw.githubusercontent.com/docker-library/postgres/62a714f93cc32220de46fd12235c9d509e3b1ad6/18/trixie/docker-entrypoint.sh";
        hash = "sha256-nEQCma4EoKedVbi/AzBwNtiQpAl50vtpgHPJBQ1LIKU=";
      };
      defaultText = "The entrypoint from the official image";
    };
    image.package = lib.mkPackageOption pkgs "postgresql_18" { };
    image.extensions = lib.mkOption {
      description = "List of postgresql extensions to include in the image";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };
  imports = [
    inputs.setup-secrets.nixosModules.default
  ]
  ++ self.lib.importsApply [
    ./grafana.nix
    ./logs.nix
    ./metrics.nix
  ];
  config = lib.mkIf cfg.enable {
    homelab.cluster.images = [ image ];
    # A password is generated only when its Secret is missing, never when the API call fails
    setup-secrets.sources = lib.listToAttrs (
      map (
        username:
        lib.nameValuePair (passwordSource username) (
          hllib.setup-secrets.kubeSecretSource pkgs {
            description = "PostgreSQL password of ${username}";
            namespace = "postgresql";
            name = "${username}-password";
            field = "password";
            generate = "head -c 1024 /dev/urandom | tr -dc A-Za-z0-9 | head -c 32";
          }
        )
      ) usernames
    );
    # The consumer reads its password from a Secret in its own namespace
    setup-secrets.destinations = [
      (hllib.setup-secrets.kubeSecretDestination pkgs {
        logPrefix = "PostgreSQL password of postgres";
        namespace = "postgresql";
        name = "postgres-password";
        data.password = passwordSource "postgres";
      })
    ]
    ++ lib.unique (
      lib.mapAttrsToList (
        _serviceName: spec:
        hllib.setup-secrets.clusterDestination pkgs {
          logPrefix = "PostgreSQL password of ${spec.username}";
          requires = [ (passwordSource spec.username) ];
          outputs = [
            "kube:postgresql/${spec.username}-password"
            "kube:${spec.namespace}/postgresql-password"
          ];
          script = ''
            setKubeSecret postgresql ${spec.username}-password password "''${${passwordSource spec.username}:?}"
            setKubeSecret ${spec.namespace} postgresql-password password "''${${passwordSource spec.username}:?}"
          '';
        }
      ) cfg.databases
    );
    assertions = lib.mapAttrsToList (namespace: names: {
      assertion = lib.length names == 1;
      message = "homelab.postgresql.databases in the namespace ${namespace} have the usernames ${lib.concatStringsSep ", " names}; they share its Secret postgresql-password, so they need one username";
    }) usernamesByNamespace;
    homelab.cluster.backup.volumes.postgresql.database-dumps = lib.mapAttrsToList (
      _serviceName: spec: "/${spec.dbName}.pgdump"
    ) dbBackups;

    # A workload named after a database waits until it can log in to it and the other databases of its namespace.
    # Started before postgresql is up or before the jobs made the databases, it crash-loops into a back-off that
    # outlasts both
    homelab.kubernetes.submodules.defaults = [
      {
        name = "workload";
        default =
          { name, ... }:
          let
            spec = cfg.databases.${name};
            dbNames = lib.mapAttrsToList (_serviceName: other: other.dbName) (
              lib.filterAttrs (_serviceName: other: other.namespace == spec.namespace) cfg.databases
            );
          in
          lib.mkIf (cfg.databases ? ${name}) {
            kubernetes.resources.deployments.${name}.spec.template.spec.initContainers.wait-for-postgresql = {
              image = "${image.buildArgs.name}:${image.imageTag}";
              imagePullPolicy = "Never";
              command = [
                "bash"
                "-c"
                "until ${
                  lib.concatMapStringsSep " && " (
                    dbName: "psql --no-psqlrc -d ${lib.escapeShellArg dbName} -c '' 2>/dev/null"
                  ) dbNames
                }; do sleep 2; done"
              ];
              env = {
                PGHOST.value = "postgresql.postgresql";
                PGCONNECT_TIMEOUT.value = "5";
                PGUSER.value = spec.username;
                PGPASSWORD.valueFrom.secretKeyRef = {
                  name = "postgresql-password";
                  key = "password";
                };
              };
              securityContext.readOnlyRootFilesystem = true;
            };
          };
      }
    ];
    # One manifest with the namespace: k3s applies manifests in the order of their names, and the jobs of a
    # `postgresql-databases` waited for the pass after the one that made the namespace
    homelab.kubernetes.submodules.instances.postgresql = {
      submodule = "manifest";
      config = {
        kubernetes.resources.persistentVolumeClaims.database-dumps.spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
          volumeMode = "Filesystem";
        };
        submodules.instances = {
          postgresql = {
            submodule = "workload";
            args = {
              dataPath = "/var/lib/postgresql";
              ports.postgresql = 5432;
              container = {
                image = "${image.buildArgs.name}:${image.imageTag}";
                imagePullPolicy = "Never";
                # POSTGRES_PASSWORD only applies at initdb, so the Secret's password is set on every start too.
                # The temporary server initdb starts takes it as well, and the loop outlasts its shutdown.
                lifecycle.postStart.exec.command = [
                  "bash"
                  "-c"
                  ''
                    until psql --no-psqlrc -qh /run/postgresql -U postgres -v ON_ERROR_STOP=1 >/dev/null <<'EOF'
                    \getenv pw POSTGRES_PASSWORD
                    ALTER USER postgres PASSWORD :'pw';
                    ${cfg.startupSql}
                    EOF
                    do sleep 1; done
                  ''
                ];
                env.POSTGRES_PASSWORD = passwordRef "postgres";
                env.POSTGRES_INITDB_ARGS.value = "-c include='/etc/postgresql/postgresql.conf'";
                volumeMounts = {
                  "/etc/postgresql".name = "config";
                  "/run/postgresql".name = "run";
                  "/tmp".name = "tmp";
                };
                livenessProbe.tcpSocket.port = "postgresql";
                readinessProbe.tcpSocket.port = "postgresql";
              };
            };
            config.kubernetes.resources = {
              # The include in POSTGRES_INITDB_ARGS fails initdb's probes, which then fall back to 20 connections and
              # 400kB of buffers; it comes after them in postgresql.conf, so these are what initdb picks otherwise
              configMaps.postgresql.data."postgresql.conf" = ''
                listen_addresses = '*'
                max_connections = 100
                shared_buffers = 128MB
                ${cfg.extraSettings}
              '';
              deployments.postgresql.spec.template.spec.volumes = {
                config.configMap.name = "postgresql";
                run.emptyDir = { };
                tmp.emptyDir = { };
              };
            };
          };
        }
        // lib.mapAttrs' (
          _serviceName: spec:
          let
            jobName = "create-${spec.dbName}-db";
          in
          lib.nameValuePair jobName {
            submodule = "job";
            args = {
              allowEgress = [ "postgresql" ];
              container = {
                image = "${image.buildArgs.name}:${image.imageTag}";
                imagePullPolicy = "Never";
                command = [
                  "bash"
                  "-ec"
                ];
                args = [
                  (lib.join "\n" (
                    # Started before postgresql accepts connections, the job would fail into the back-off of its pod
                    [ "until pg_isready --quiet; do sleep 2; done" ]
                    ++
                      map (cmd: ''psql --no-psqlrc --set ON_ERROR_STOP=1 --pset pager=off -f <(printf "%s" "${cmd}")'')
                        # format() quotes the names: a hyphen in a database name needs quotes, and a double quote would
                        # end the shell string around the command
                        (
                          [
                            "SELECT format('CREATE USER %I', '${spec.username}') WHERE NOT EXISTS (SELECT FROM pg_user WHERE usename = '${spec.username}')\\gexec"
                            "\\getenv pw USER_PASSWORD\nSELECT format('ALTER USER %I PASSWORD %L', '${spec.username}', :'pw')\\gexec"
                            "SELECT format('CREATE DATABASE %I', '${spec.dbName}') WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${spec.dbName}')\\gexec"
                            "SELECT format('ALTER DATABASE %I OWNER TO %I', '${spec.dbName}', '${spec.username}')\\gexec"
                          ]
                        )
                    ++ map (
                      cmd:
                      ''psql --no-psqlrc --set ON_ERROR_STOP=1 --pset pager=off -d ${spec.dbName} -f <(printf "%s" "${cmd}")''
                    ) (spec.setupCommands)
                  ))
                ];
                env = {
                  PGHOST.value = "postgresql.postgresql";
                  PGUSER.value = "postgres";
                  PGPASSWORD = passwordRef "postgres";
                  USER_PASSWORD = passwordRef spec.username;
                };
              };
            };
            config.kubernetes.resources.jobs.${jobName}.spec.template.spec.restartPolicy = "OnFailure";
          }
        ) cfg.databases
        // lib.mapAttrs' (
          _serviceName: spec:
          let
            jobName = "backup-${spec.dbName}-db";
          in
          lib.nameValuePair jobName {
            submodule = "cronjob";
            args = {
              inherit (spec.backup) schedule;
              allowEgress = [ "postgresql" ];
              container = {
                image = "${image.buildArgs.name}:${image.imageTag}";
                command = [ "pg_dump" ];
                args = [
                  "--username=postgres"
                  "--dbname=${spec.dbName}"
                  "--blobs"
                  "--quote-all-identifiers"
                  "--format=custom"
                  "--file=/dumps/${spec.dbName}.pgdump"
                ];
                env = {
                  PGHOST.value = "postgresql.postgresql";
                  PGUSER.value = "postgres";
                  PGPASSWORD = passwordRef "postgres";
                };
                volumeMounts."/dumps".name = "data";
              };
            };
            config.kubernetes.resources.cronJobs.${jobName}.spec.jobTemplate.spec.template.spec.volumes.data.persistentVolumeClaim.claimName =
              "database-dumps";
          }
        ) dbBackups;
      };
    };
  };
}
