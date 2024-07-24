job "${nomad_namespace}-backup-db" {

  datacenters = ["${datacenter}"]
  namespace   = "${nomad_namespace}"

  type = "batch"

  periodic {
    cron             = "${backup_cron}"
    prohibit_overlap = true
  }

  vault {
    policies    = ["${vault_acl_policy_name}"]
    change_mode = "restart"
  }

  group "g-backup-db" {
    count = 1

    task "dump-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "ans/mariadb-ssh:10.4.8"
        command = "bash"
        args    = ["/secrets/backup.sh"]
      }

      resources {
        cpu    = 500
        memory = 2048
      }

      template {
        change_mode = "noop"
        destination = "/secrets/id_rsa"
        perms       = "600"
        data        = <<EOH
{{with secret "${vault_secrets_engine_name}"}}{{.Data.data.rsa_private_key}}{{end}}
        EOH
      }

      template {
        # " noop " - take no action (continue running the task)
        change_mode = "noop"
        destination = "secrets/backup.sh"
        data        = <<EOH
#!/bin/bash
# Variables globales
HOME_DIR="$(pwd)"
DUMP_DIR="$${NOMAD_ALLOC_DIR}/data"
LOG_DIR="$${HOME_DIR}"

LOG_FILE="$${NOMAD_ALLOC_DIR}/logs/mantisbt_dumpdb$${TODAY}.log"
TMP_FILE="$${NOMAD_ALLOC_DIR}/tmp/mantisbt_dumpdb$${TODAY}.tmp"

DUMP_FILE="mysqldump_mantisbt$${TODAY}.sql.gz"

# récupère l'address de Mariadb dans Consul
{{range service ( print (env "NOMAD_NAMESPACE") "-db") }}
DATABASE_IP={{.Address}}
DATABASE_PORT={{.Port}}
{{end}}

# récupère les secrets dans Vault
{{with secret "${vault_secrets_engine_name}"}}
DATABASE_USER={{.Data.data.db_username}}
DATABASE_PASSWD={{.Data.data.db_password}}
DATABASE_NAME={{.Data.data.database_name}}
BACKUP_SERVER={{.Data.data.backup_server}}
TARGET_FOLDER={{.Data.data.backup_folder}}
SSH_USER={{.Data.data.ssh_user}}
{{end}}

VERBOSE=1

### Set bins path ###
GZIP=$$(which gip)
MYSQL=$$(which mysql)
MYSQLDUMP=$$(which mysqldump)
SSH=$$(which ssh)
MYSQLADMIN=$$(which mysqladmin)
GREP=$$(which grep)

#####################################
### ----[ No Editing below ]------###
#####################################
### Default time format ###
TIME_FORMAT='%Y%m%d_%H%M%S'

### Make a backup ###
backup_mysql_rsnapshot() {
    local tTime=$$(date +"$${TIME_FORMAT}")
    local FILE="$${TARGET_FOLDER}/mysqldump_$${DATABASE_NAME}_$${tTime}.gz"

    [ $$VERBOSE -eq 1 ] && echo -n "$${MYSQLDUMP} --single-transaction -u $${DATABASE_USER} -h $${DATABASE_IP} -P $${DATABASE_PORT} -pDATABASE_PASSWD $${DATABASE_NAME} | $${GZIP} -9 | $SSH -o StrictHostKeyChecking=accept-new -i /secrets/id_rsa $${SSH_USER}@$${BACKUP_SERVER} "cat >$${FILE}" .."
    $${MYSQLDUMP} --single-transaction -u $${DATABASE_USER} -h $${DATABASE_IP} -P $${DATABASE_PORT} -p$${DATABASE_PASSWD} $${DATABASE_NAME} | $${GZIP} -9 | $SSH -o StrictHostKeyChecking=accept-new -i /secrets/id_rsa $${SSH_USER}@$${BACKUP_SERVER} "cat > $${FILE}"
    [ $$VERBOSE -eq 1 ] && echo ""
    [ $$VERBOSE -eq 1 ] && echo "*** Backup done [ files wrote to $TARGET_FOLDER] ***"
}

### Die on demand with message ###
die() {
    echo "$@"
    exit 99
}

### Make sure bins exists.. else die
verify_bins() {
    [ ! -x $$GZIP ] && die "File $GZIP does not exists. Make sure correct path is set in $0."
    [ ! -x $$MYSQL ] && die "File $MYSQL does not exists. Make sure correct path is set in $0."
    [ ! -x $$MYSQLDUMP ] && die "File $MYSQLDUMP does not exists. Make sure correct path is set in $0."
    [ ! -x $$SSH ] && die "File $SSH does not exists. Make sure correct path is set in $0."
    [ ! -x $$MYSQLADMIN ] && die "File $MYSQLADMIN does not exists. Make sure correct path is set in $0."
    [ ! -x $$GREP ] && die "File $GREP does not exists. Make sure correct path is set in $0."
}

### Make sure we can connect to server ... else die
verify_mysql_connection() {
    $$MYSQLADMIN -u $$DATABASE_USER -h $$DATABASE_IP -p$$DATABASE_PASSWD ping | $$GREP 'alive' >/dev/null
    [ $$? -eq 0 ] || die "Error: Cannot connect to MySQL Server. Make sure username and password are set correctly in $$0"
}

### main ####
verify_bins
verify_mysql_connection
backup_mysql_rsnapshot
EOH
      }
    }

    task "log-shipper" {
      driver = "docker"
      config {
        image = "${log_shipper_image}:${log_shipper_tag}"
      }
      resources {
        cpu    = 100
        memory = 150
      }
      restart {
        interval = "3m"
        attempts = 5
        delay    = "15s"
        mode     = "delay"
      }
      meta {
        INSTANCE = "$${NOMAD_ALLOC_NAME}"
      }
      template {
        destination = "local/file.env"
        change_mode = "restart"
        env         = true
        data        = <<EOH
REDIS_HOSTS={{ range service "PileELK-redis" }}{{ .Address }}:{{ .Port }}{{ end }}
PILE_ELK_APPLICATION=${nomad_namespace}
EOH        
      }
    }

  }
}