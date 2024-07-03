project = "${workspace.name}" # exemple : forge/mantisbt-dev

labels = { "domaine" = "forge" }

# https://developer.hashicorp.com/waypoint/docs/waypoint-hcl/runner
runner {
  enabled = true
  profile = "common-odr"
  data_source "git" {
    url                         = "https://github.com/ansforge/forge-mantisbt.git"
    ref                         = "gitref"
    path                        = "mantisbt-db"
    ignore_changes_outside_path = true
  }
  poll {
    # à mettre à true pour déployer automatiquement en cas de changement dans la branche
    enabled  = true
    interval = "60s"
  }
}

############## APPs ##############

# --- MariaDB ---

app "forge-mantisbt-app" {
  build {
    use "docker-ref" {
      image = var.webapp_image
      tag   = var.webapp_tag
    }
  }
  deploy {
    use "nomad-jobspec" {
      jobspec = templatefile("${path.app}/forge-mantisbt-app.nomad.tpl", {
        datacenter                = var.datacenter
        vault_secrets_engine_name = var.vault_secrets_engine_name

        nomad_namespace = var.nomad_namespace
        image           = var.webapp_image
        tag             = var.webapp_tag

        log_shipper_image = var.log_shipper_image
        log_shipper_tag   = var.log_shipper_tag
      })
    }
  }
}

# --- MariaDB ---

app "forge-mantisbt-db" {
  build {
    use "docker-ref" {
      image = var.database_image
      tag   = var.database_tag
    }
  }
  deploy {
    use "nomad-jobspec" {
      jobspec = templatefile("${path.app}/forge-mantisbt-db.nomad.tpl", {
        datacenter                = var.datacenter
        vault_acl_policy_name     = var.vault_acl_policy_name
        vault_secrets_engine_name = var.vault_secrets_engine_name

        nomad_namespace = var.nomad_namespace
        image           = var.database_image
        tag             = var.database_tag

        log_shipper_image = var.log_shipper_image
        log_shipper_tag   = var.log_shipper_tag
      })
    }
  }
}

############## variables ##############

# --- variable common ---

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

# --- MariaDB ---

variable "database_image" {
  type    = string
  default = "mariadb"
}

variable "database_tag" {
  type    = string
  default = "10.4"
}

# --- Mantis ---

variable "webapp_image" {
  type    = string
  default = "xlrl/mantisbt"
}

variable "webapp_tag" {
  type    = string
  default = "latest"
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