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
        image   = "${image}:${tag}"
        command = "bash"
        args    = ["/secrets/backup.sh"]
      }

      resources {
        cpu    = 20
        memory = 512
      }

      template {
        # " noop " - take no action (continue running the task)
        change_mode = "noop"

        destination = "secrets/backup.sh"
        data        = <<EOH
#!/bin/bash
# Variables globales
TODAY="_$(date "+%Y%m%d_%H%M%S")"
HOME_DIR="$(pwd)"
DUMP_DIR="$${NOMAD_ALLOC_DIR}/data"
LOG_DIR="$${HOME_DIR}"
DUMP_FILE="mysqldump_mantisbt.sql"
ZIP_FILE="$${DUMP_FILE}.gz"
LOG_FILE="$${NOMAD_ALLOC_DIR}/logs/mantisbt_dumpdb$${TODAY}.log"
TMP_FILE="$${NOMAD_ALLOC_DIR}/tmp/mantisbt_dumpdb$${TODAY}.tmp"

# récupère l'address de Mariadb dans Consul
{{range service ( print (env "NOMAD_NAMESPACE") "-db") }}
DATABASE_IP={{.Address}}
DATABASE_PORT={{.Port}}
{{end}}

# récupère les secrets dans Vault
{{with secret "${vault_secrets_engine_name}"}}
DATABASE_USER={{.Data.data.mariadb_username}}
DATABASE_PASSWD={{.Data.data.mariadb_password}}
DATABASE_NAME={{.Data.data.database_name}}
{{end}}

# Generation du DUMP de la base
echo -e "Generation du dump de la base \"$${DUMP_DIR}/$${DUMP_FILE}\"..."
mysqldump -v -h $${DATABASE_IP} -P $${DATABASE_PORT} -u $${DATABASE_USER} -p$${DATABASE_PASSWD} $${DATABASE_NAME} > "$${DUMP_DIR}/$${DUMP_FILE}" 2>$${TMP_FILE}
RET_CODE=$?
if [ $${RET_CODE} -ne 0 ]
then
    echo -e "[ERROR] - En execution de la commande : mysqldump -h $${DATABASE_IP} -P $${DATABASE_PORT} -u $${DATABASE_USER} -p$${DATABASE_PASSWD} $${DATABASE_NAME} > \"$${DUMP_DIR}/$${DUMP_FILE}\" !"
    cat $${TMP_FILE} >> $${LOG_FILE}
    echo -e "Exit code : $${RET_CODE}"
    exit 1
else
    echo "(OK)"
fi

cat $${TMP_FILE} >> $${LOG_FILE}

# Zippage du dump de la base
echo "Zippage du dump, l'enregistrer dans : \"$${DUMP_DIR}/$${ZIP_FILE}\"..."
cd "$${DUMP_DIR}" && gzip "$${DUMP_FILE}" > $${TMP_FILE} 2>&1
RET_CODE=$?
cd "$${HOME_DIR}"
if [ $${RET_CODE} -ne 0 ]
then
    echo -e "[ERROR] - En execution de la commande : gzip \"$${DUMP_FILE}\" ! "
    cat $${TMP_FILE} >> $${LOG_FILE}
    echo -e "Exit code : $${RET_CODE}"
    exit 1
else
    echo "(OK)"
fi

cat $${TMP_FILE} >> $${LOG_FILE}

# Compte rendu du fichier dump cree par le traitement
echo -e "(Fin du task 'dump-db')"
EOH

      }
    }

    task "send-dump" {
      driver = "docker"
      config {
        image   = "ans/scp-client"
        command = "bash"
        args    = ["/secrets/send.sh"]
      }

      # log-shipper
      leader = true

      template {
        change_mode = "noop"
        destination = "/secrets/id_rsa"
        perms       = "600"
        data        = <<EOH
{{with secret "${vault_secrets_engine_name}"}}{{.Data.data.rsa_private_key}}{{end}}
        EOH
      }

      template {
        change_mode = "noop"
        destination = "/secrets/send.sh"
        data        = <<EOH
#!/bin/bash
TODAY="_$(date "+%Y%m%d_%H%M%S")"
DUMP_DIR="$${NOMAD_ALLOC_DIR}/data"
DUMP_FILE="mysqldump_mantisbt$${TODAY}.sql.gz"

echo -e "Envois fichier dump vers server backup et le renommer à \"$${DUMP_FILE}\" ..."
{{with secret "${vault_secrets_engine_name}"}}
BACKUP_SERVER={{.Data.data.backup_server}}
TARGET_FOLDER={{.Data.data.backup_folder}}
SSH_USER={{.Data.data.ssh_user}}
{{end}}
scp -o StrictHostKeyChecking=accept-new -i /secrets/id_rsa $${DUMP_DIR}/mysqldump_mantisbt.sql.gz $${SSH_USER}@$${BACKUP_SERVER}:$${TARGET_FOLDER}/$${DUMP_FILE}
RET_CODE=$?
if [ $${RET_CODE} -ne 0 ]
then
    echo -e "[ERROR] - En execution de la commande : scp -o StrictHostKeyChecking=accept-new -i /secrets/id_rsa \"$${DUMP_DIR}\"/mysqldump_mantisbt.sql.gz \"$${SSH_USER}\"@\"$${BACKUP_SERVER}\":\"$${TARGET_FOLDER}\"/\"$${DUMP_FILE}\" ! "
    echo -e "Exit code : $${RET_CODE}"
    exit 1
else
    echo "(OK)"
fi

echo "(Fin du Task 'send-dump')"
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