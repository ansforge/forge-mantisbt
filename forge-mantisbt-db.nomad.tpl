job "forge-mantisbt-db" {
  datacenters = ["${datacenter}"]
  namespace   = "${nomad_namespace}"

  type = "service"

  update {
    stagger      = "30s"
    max_parallel = 1
    auto_revert  = true
  }

  vault {
    policies    = ["forge"]
    change_mode = "restart"
  }

  group "group-forge-mantis-db" {
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
        image = "${image}:${tag}"
        ports = ["db"]
        volumes = [
          "name=$${NOMAD_JOB_NAME},io_priority=high,size=20,repl=2:/var/lib/mysql"
        ]
        volume_driver = "pxd"
      }

      # log-shipper
      leader = true

      template {
        destination = "secrets/file.env"
        env         = true
        data        = <<EOH
{{with secret "${vault_secrets_engine_name}"}}
MARIADB_USER="{{.Data.data.mariadb_username}}"
MARIADB_ROOT_PASSWORD="{{.Data.data.mariadb_rootpassword}}"
MARIADB_PASSWORD="{{.Data.data.mariadb_password}}"
MARIADB_DATABASE="{{.Data.data.database_name}}"
{{end}}
EOH
      }

      resources {
        cpu    = 500
        memory = 2048
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
