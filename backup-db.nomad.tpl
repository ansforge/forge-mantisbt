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

      leader = true

      config {
        image   = "ans/mariadb-ssh:10.4.8"
        command = "bash"
        args    = ["/secrets/backup.sh"]
      }

      resources {
        cpu    = ${backup_db_ressource_cpu}
        memory = ${backup_db_ressource_mem}
      }

      template {
        change_mode = "noop"
        destination = "/secrets/id_rsa"
        perms       = "400"
        data        = <<EOH
{{with secret "${vault_secrets_engine_name}"}}{{.Data.data.rsa_private_key}}{{end}}
        EOH
      }

      template {
        # " noop " - take no action (continue running the task)
        change_mode = "noop"
        destination = "/secrets/backup.sh"
        data        = <<EOH
#!/bin/bash
# Variables globales
TODAY="_$(date "+%Y%m%d_%H%M%S")"
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

# Generation du DUMP de la base
echo -e "Generation du dump de la base :
mysqldump -v -h $${DATABASE_IP} -P $${DATABASE_PORT} -u $${DATABASE_USER} -p*** $${DATABASE_NAME} | gzip -c >$${DUMP_DIR}/mysqldump_mantisbt.sql.gz 2>$${TMP_FILE} ..."

mysqldump -v -h $${DATABASE_IP} -P $${DATABASE_PORT} -u $${DATABASE_USER} -p$${DATABASE_PASSWD} $${DATABASE_NAME} | gzip -c >$${DUMP_DIR}/mysqldump_mantisbt.sql.gz 2>$${TMP_FILE}

RET_CODE=$?
if [ $${RET_CODE} -ne 0 ]
then
    echo -e "[ERROR] - En execution de la commande mysqldump"
    echo -e "Exit code : $${RET_CODE}"
    exit 1
else
    echo "OK!"
fi

echo -e "Envoyer le dump vers la VM de sauvegarde :
scp -o StrictHostKeyChecking=accept-new -i /secrets/id_rsa $${DUMP_DIR}/mysqldump_mantisbt.sql.gz $${SSH_USER}@$${BACKUP_SERVER}:$${TARGET_FOLDER}/$${DUMP_FILE}"

scp -o StrictHostKeyChecking=accept-new -i /secrets/id_rsa $${DUMP_DIR}/mysqldump_mantisbt.sql.gz $${SSH_USER}@$${BACKUP_SERVER}:$${TARGET_FOLDER}/$${DUMP_FILE}

RET_CODE=$?
if [ $${RET_CODE} -ne 0 ]
then
    echo -e "[ERROR] - En execution de la commande scp"
    echo -e "Exit code : $${RET_CODE}"
    exit 1
else
    echo "OK!"
fi

# Compte rendu du fichier dump cree par le traitement
echo -e "(Fin du task 'dump-db')"
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