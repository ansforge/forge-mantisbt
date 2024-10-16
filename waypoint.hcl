project = "${workspace.name}" # exemple : forge-mantisbt-dev

labels = { "domaine" = "forge" }

runner {
  enabled = true
  profile = "common-odr"
  data_source "git" {
    url = "https://github.com/ansforge/forge-mantisbt.git"
    ref = "gitref"
  }
  poll {
    # à mettre à true pour déployer automatiquement en cas de changement dans la branche
    enabled = false
    # interval = "60s"
  }
}

############## APPs ##############

# --- MantisBT APP ---

app "mantisbt-app" {
  build {
    use "docker-ref" {
      image = var.webapp_image
      tag   = var.webapp_tag
    }
  }
  deploy {
    use "nomad-jobspec" {
      jobspec = templatefile("${path.app}/mantisbt-app.nomad.tpl", {
        datacenter                = var.datacenter
        vault_acl_policy_name     = var.vault_acl_policy_name
        vault_secrets_engine_name = var.vault_secrets_engine_name

        nomad_namespace        = var.nomad_namespace
        image                  = var.webapp_image
        tag                    = var.webapp_tag
        mantisbt_fqdn          = var.mantisbt_fqdn
        mantis_enable_admin    = var.mantis_enable_admin
        mantisbt_ressource_cpu = var.mantisbt_ressource_cpu
        mantisbt_ressource_mem = var.mantisbt_ressource_mem

        log_shipper_image = var.log_shipper_image
        log_shipper_tag   = var.log_shipper_tag
      })
    }
  }
}

# --- MariaDB ---

app "mantisbt-db" {
  build {
    use "docker-ref" {
      image = var.database_image
      tag   = var.database_tag
    }
  }
  deploy {
    use "nomad-jobspec" {
      jobspec = templatefile("${path.app}/mantisbt-db.nomad.tpl", {
        datacenter                = var.datacenter
        vault_acl_policy_name     = var.vault_acl_policy_name
        vault_secrets_engine_name = var.vault_secrets_engine_name

        nomad_namespace  = var.nomad_namespace
        image            = var.database_image
        tag              = var.database_tag
        db_ressource_cpu = var.db_ressource_cpu
        db_ressource_mem = var.db_ressource_mem

        log_shipper_image = var.log_shipper_image
        log_shipper_tag   = var.log_shipper_tag
      })
    }
  }
}

# --- Backup DB ---

app "backup-db" {
  build {
    use "docker-ref" {
      image = var.database_image
      tag   = var.database_tag
    }
  }
  deploy {
    use "nomad-jobspec" {
      jobspec = templatefile("${path.app}/backup-db.nomad.tpl", {
        datacenter                = var.datacenter
        vault_secrets_engine_name = var.vault_secrets_engine_name
        vault_acl_policy_name     = var.vault_acl_policy_name
        nomad_namespace           = var.nomad_namespace

        image                   = "ans/mariadb-ssh"
        tag                     = "10.4.8"
        backup_db_ressource_cpu = var.backup_db_ressource_cpu
        backup_db_ressource_mem = var.backup_db_ressource_mem
        backup_cron             = var.backup_cron

        log_shipper_image = var.log_shipper_image
        log_shipper_tag   = var.log_shipper_tag
      })
    }
  }
}

############## variables ##############

# --- common ---

# Convention :
# [NOM-WORKSPACE] = [waypoint projet name] = [nomad namespace name] = [Vault ACL Policies Name] = [Valut Secrets Engine Name]

variable "datacenter" {
  type    = string
  default = "henix_docker_platform_dev"
  env     = ["NOMAD_DC"]
}

# ${workspace.name} : waypoint workspace name

variable "nomad_namespace" {
  type    = string
  default = "${workspace.name}"
}

variable "vault_acl_policy_name" {
  type    = string
  default = "${workspace.name}"
}

variable "vault_secrets_engine_name" {
  type    = string
  default = "${workspace.name}"
}

# --- Mantis DB ---

variable "database_image" {
  type    = string
  default = "mariadb"
}

variable "database_tag" {
  type    = string
  default = "10.4"
}

variable "db_ressource_cpu" {
  type    = number
  default = 500
}

variable "db_ressource_mem" {
  type    = number
  default = 1024
}

# --- Mantis App---

variable "webapp_image" {
  type    = string
  default = "ans/mantisbt"
}

variable "webapp_tag" {
  type    = string
  default = "2.25.2-php7"
}

variable "mantisbt_fqdn" {
  type    = string
  default = "mantis.forge.esante.gouv.fr"
}

variable "mantis_enable_admin" {
  type    = string
  default = "0" # "0" = disable; "1" = enable
}

variable "mantisbt_ressource_cpu" {
  type    = number
  default = 2048
}

variable "mantisbt_ressource_mem" {
  type    = number
  default = 5120
}

# --- Backup-db ---
variable "backup_cron" {
  type    = string
  default = "0 04 * * *"
}

variable "backup_db_ressource_cpu" {
  type    = number
  default = 2048
}

variable "backup_db_ressource_mem" {
  type    = number
  default = 512
}

# --- log-shipper ---

variable "log_shipper_image" {
  type    = string
  default = "ans/nomad-filebeat"
}

variable "log_shipper_tag" {
  type    = string
  default = "8.2.3-2.0"
}
