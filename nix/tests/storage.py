kubectl = "k3s kubectl"
pg = f"{kubectl} -n postgresql"

node.start()
node.wait_for_unit("k3s.service")
node.wait_until_succeeds(f"{kubectl} wait node node --for=condition=Ready --timeout=10s", timeout=600)

with subtest("storage: nfs-provisioner creates a volume with the configured mode and owner"):
    # The only published image, v4.0.2, ignored NFS_DEFAULT_MODE and made every volume 0777
    try:
        node.wait_until_succeeds(
            f"{kubectl} -n nfs-provisioner rollout status deploy/nfs-subdir-external-provisioner --timeout=10s",
            timeout=600,
        )
    except Exception:
        node.execute(
            f"{kubectl} -n nfs-provisioner describe pods >&2; "
            f"{kubectl} -n nfs-provisioner logs deploy/nfs-subdir-external-provisioner --all-containers >&2"
        )
        raise
    node.succeed(
        f"{kubectl} apply -f - <<'EOF'\n"
        "apiVersion: v1\nkind: PersistentVolumeClaim\n"
        "metadata: {name: mode-test, namespace: default}\n"
        "spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 1Mi}}}\n"
        "EOF"
    )
    node.wait_until_succeeds(
        f"test \"$({kubectl} -n default get pvc mode-test -o jsonpath='{{.status.phase}}')\" = Bound", timeout=300
    )
    got = node.succeed("stat -c '%a %u:%g' /srv/nfs/default-mode-test").strip()
    assert got == "750 900:900", got

with subtest("storage: postgresql has generated passwords from Secrets, consumers get copies, the superuser's re-set at every start"):
    node.wait_until_succeeds(f"{kubectl} get namespace postgresql", timeout=600)
    # The consumer's namespace, which its own module would make
    node.succeed(f"{kubectl} create namespace myapp")
    # The test node doesn't enable setup-secrets' activation and service; a real one runs this on every deploy
    node.succeed("setup-secrets --auto")
    secret = f"{kubectl} -n {{}} get secret {{}} -o jsonpath='{{{{.data.password}}}}' | base64 -d"
    first = node.succeed(secret.format("postgresql", "postgres-password"))
    node.succeed("setup-secrets --auto")
    assert node.succeed(secret.format("postgresql", "postgres-password")) == first, "setup-secrets replaced a password"
    # The consumer's copy in its own namespace
    node.succeed(f"cmp <({secret.format('postgresql', 'myapp-password')}) <({secret.format('myapp', 'postgresql-password')})")
    try:
        node.wait_until_succeeds(f"{pg} rollout status deploy/postgresql --timeout=10s", timeout=600)
    except Exception:
        node.execute(
            f"{pg} describe pods | tail -40 >&2; {pg} logs deploy/postgresql --all-containers --previous --tail=60 >&2;"
            f" {pg} logs deploy/postgresql --all-containers --tail=60 >&2"
        )
        raise
    # initdb's fallback of 20 connections and 400kB of buffers starves index builds
    settings = node.succeed(
        f"{pg} exec deploy/postgresql -- psql -h /run/postgresql -U postgres -tAc"
        " \"SELECT current_setting('shared_buffers') || ' ' || current_setting('max_connections')\""
    ).strip()
    assert settings == "128MB 100", settings
    for db in ["myapp", "myapp-log"]:
        node.wait_until_succeeds(f"{pg} wait job/create-{db}-db --for=condition=Complete --timeout=10s", timeout=600)

    def login(user, password_cmd, db="postgres"):
        """Logs in over TCP to the pod's IP, which pg_hba sends to password authentication"""
        pods = f"{pg} get pod -l app.kubernetes.io/name=postgresql -o jsonpath='{{.items[*].status.podIP}}'"
        node.wait_until_succeeds(f"test $({pods} | wc -w) = 1", timeout=120)
        ip = node.succeed(pods).strip()
        return (
            f"{password_cmd} | {pg} exec -i deploy/postgresql -- bash -c"
            f" 'PGPASSWORD=$(cat) psql --no-psqlrc -h {ip} -U {user} -d {db} -c \"SELECT 1\"'"
        )

    node.succeed(login("myapp", secret.format("postgresql", "myapp-password")))
    node.succeed(login("myapp", secret.format("postgresql", "myapp-password"), db="myapp-log"))
    node.fail(login("myapp", "echo myapp"))
    node.succeed(login("postgres", secret.format("postgresql", "postgres-password")))
    node.fail(login("postgres", "echo postgres"))
    node.succeed(f"{pg} create job backup-test --from=cronjob/backup-myapp-db")
    node.wait_until_succeeds(f"{pg} wait job/backup-test --for=condition=Complete --timeout=10s", timeout=300)

    # An existing data dir keeps initdb's password; the restart has to set the Secret's
    node.succeed(
        f"{kubectl} -n postgresql create secret generic postgres-password --from-literal=password=rotated"
        f" --dry-run=client -o yaml | {kubectl} apply -f -"
    )
    node.succeed(f"{pg} rollout restart deploy/postgresql && {pg} rollout status deploy/postgresql --timeout=300s")
    node.succeed(login("postgres", "echo rotated"))
    node.fail(login("postgres", "echo " + first))

    # The pod's socket trusts every local connection, so no host user may reach it through the kubelet's emptyDir
    socks = node.succeed("find /var/lib/kubelet/pods -name .s.PGSQL.5432").split()
    assert socks, "no postgresql socket under /var/lib/kubelet/pods"
    for sock in socks:
        node.fail(f"su -s /bin/sh admin -c 'test -e {sock}'")
