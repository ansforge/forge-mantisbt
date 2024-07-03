job "${nomad_namespace}-app" {
  datacenters = ["${datacenter}"]
  namespace   = "${nomad_namespace}"

  type = "service"

  vault {
    policies    = ["${vault_acl_policy_name}"]
    change_mode = "restart"
  }

  update {
    stagger      = "30s"
    max_parallel = 1
    auto_revert  = true
  }

  group "group-mantis-app" {
    count = "1"

    restart {
      attempts = 3
      delay    = "60s"
      interval = "1h"
      mode     = "fail"
    }

    # install only on "data" nodes
    constraint {
      attribute = "$${node.class}"
      value     = "data"
    }

    network {
      port "http" {
        to = 8989
      }
    }

    task "mantisbt" {
      driver = "docker"

      # log-shipper
      leader = true

      config {
        image = "${image}:${tag}"
        ports = ["http"]
      }

      template {
        data = <<EOH
MANTIS_TIMEZONE=Europe/Paris
MANTIS_ENABLE_ADMIN=1
EOH

        destination = "secrets/file.env"
        change_mode = "restart"
        env         = true
      }

      resources {
        cpu    = 2048
        memory = 5120
      }

      service {
        name = "$${NOMAD_JOB_NAME}"
        tags = ["urlprefix-${mantisbt_fqdn}"]
        port = "http"
        check {
          name     = "alive"
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "5s"
          port     = "http"
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
