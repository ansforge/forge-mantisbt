job "${nomad_namespace}-db" {

  datacenters = ["${datacenter}"]
  namespace   = "${nomad_namespace}"

  type = "service"

  update {
    stagger      = "30s"
    max_parallel = 1
    auto_revert  = true
  }

  vault {
    policies    = ["${vault_acl_policy_name}"]
    change_mode = "restart"
  }

  group "group-mantis-db" {
    count = "1"
    # install only on "data" nodes
    constraint {
      attribute = "$${node.class}"
      value     = "data"
    }

    restart {
      attempts = 3
      delay    = "60s"
      interval = "1h"
      mode     = "fail"
    }

    network {
      port "db" { to = 3306 }
    }

    task "mariadb" {
      driver = "docker"
      config {
        image   = "${image}:${tag}"
        command = "--max_allowed_packet=500M"
        ports   = ["db"]
        volumes = [
          "name=$${NOMAD_JOB_NAME},io_priority=high,size=50,repl=1:/var/lib/mysql"
        ]
        volume_driver = "pxd"
      }

      # log-shipper
      leader = true

      template {
        data = <<EOH
{{with secret "${vault_secrets_engine_name}"}}
MARIADB_USER="{{.Data.data.db_username}}"
MARIADB_ROOT_PASSWORD="{{.Data.data.db_root_password}}"
MARIADB_PASSWORD="{{.Data.data.db_password}}"
MARIADB_DATABASE="{{.Data.data.database_name}}"
{{end}}
EOH

        destination = "secrets/file.env"
        env         = true
      }

      resources {
        cpu    = ${db_ressource_cpu}
        memory = ${db_ressource_mem}
      }
      service {
        name = "$${NOMAD_JOB_NAME}"
        port = "db"
        tags = ["urlprefix-:3306 proto=tcp"]
        check {
          type     = "tcp"
          port     = "db"
          name     = "check_mysql"
          interval = "120s"
          timeout  = "2s"
        }
        check_restart {
          limit           = 3
          grace           = "120s"
          ignore_warnings = true
        }
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
    } #end log-shipper
  }
}
