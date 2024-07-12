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
        to = 80
      }
    }

    task "mantisbt" {
      driver = "docker"

      # log-shipper
      leader = true

      config {
        image = "${image}:${tag}"
        ports = ["http"]

        mount {
          type     = "bind"
          target   = "/var/www/html/config/config_inc.php"
          source   = "secrets/config_inc.php"
          readonly = false
          bind_options {
            propagation = "rshared"
          }
        }
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

      template {
        data        = <<EOH
<?php
{{range service ( print (env "NOMAD_NAMESPACE") "-db") }}
$g_hostname='{{.Address}}:{{.Port}}';{{end}}
{{with secret "${vault_secrets_engine_name}"}}
$g_db_type='mysqli';
$g_database_name='{{.Data.data.database_name}}';
$g_db_username='{{.Data.data.db_username}}';
$g_db_password='{{.Data.data.db_password}}';
{{end}}
$g_crypto_master_salt = 'scrmoJSscIpgHQevBis';      # Random string of at least 16 chars, unique to the installation

#LDAP
$g_login_method=LDAP;
$g_ldap_protocol_version=3;
$g_ldap_server='ldap://{{ range service "openldap-forge" }}{{.Address}}:{{.Port}}{{ end }}';
{{with secret "forge/openldap"}}
$g_ldap_root_dn='{{.Data.data.ldap_root}}';
$g_ldap_bind_dn='cn=Manage,dc=asipsante,dc=fr';
$g_ldap_bind_password='{{.Data.data.admin_password}}';
$g_use_ldap_email = ON;
$g_use_ldap_realname = ON;
$g_ldap_follow_referrals =OFF;
$g_ldap_use_starttls = OFF;
{{end}}


#Logo
$g_logo_image='images/ans_logo.png';
# --- anonymous login -----------                     
# Allow anonymous login                               
$g_allow_anonymous_login = OFF;                 
#$g_anonymous_account = 'guest'; 

$g_auto_set_status_to_assigned=OFF;
$g_bug_reopen_status= CONFIRMED;
$g_use_jpgraph=ON;
$g_jpgraph_path = '.' . DIRECTORY_SEPARATOR . 'library' . DIRECTORY_SEPARATOR . 'jpgraph' . DIRECTORY_SEPARATOR;   # dont forget the ending slash!
$g_jpgraph_antialias    = ON;
$g_graph_font = '';
$g_graph_window_width = 800;
$g_graph_bar_aspect = 0.9;
$g_graph_summary_graphs_per_row = 2;
$g_default_graph_type = 0;
$g_graph_colors = array('coral', 'red', 'blue', 'black', 'green', 'orange', 'pink', 'brown', 'gray',
                'blueviolet','chartreuse','magenta','purple3','teal','tan','olivedrab','magenta');
$g_enable_email_notification = ON; //enables the email messages
$g_webmaster_email='ASIP-Support-TRA@esante.gouv.fr';
$g_administrator_email='erick.riegel.ext@esante.gouv.fr';
$g_from_email='mantis@esante.gouv.fr';
# the sender name, part of 'From: ' header in emails
$g_from_name = 'Gestion des anomalies Mantis (ne pas répondre)';
# the return address for bounced mail
$g_return_path_email    = 'mantis.EXT@esante.gouv.fr';
$g_phpMailer_method=PHPMAILER_METHOD_SMTP;
$g_smtp_host='e-ac-smtp01.asip.hst.fluxus.net';
$g_email_send_using_cronjob = OFF;
$g_show_realname = ON;
$g_allow_signup = OFF;
$g_default_language = 'french';
$g_notify_flags['new']['threshold_min'] = SENIOR_DEVELOPER;
$g_notify_flags['new']['threshold_max'] = MANAGER;
# Notification du responsble de développement pour tous les événements du projet
$g_default_notify_flags['threshold_min'] = SENIOR_DEVELOPER;
$g_default_notify_flags['threshold_max'] = SENIOR_DEVELOPER;
$g_status_enum_workflow[NEW_]= '10:new,20:feedback,40:confirmed,45:monitored,50:assigned,80:resolved';
$g_status_enum_workflow[FEEDBACK] = '10:new,20:feedback,40:confirmed,45:monitored,90:closed';
$g_manage_project_threshold = SENIOR_DEVELOPER;
# $g_status_enum_workflow[ACKNOWLEDGED] = '20:feedback,30:acknowledged,40:confirmed,50:assigned,80:resolved';
$g_status_enum_workflow[CONFIRMED] = '20:feedback,40:confirmed,45:monitored,50:assigned,80:resolved';
$g_status_enum_workflow['MONITORED'] = '20:feedback,40:confirmed,50:assigned,80:resolved';
$g_status_enum_workflow[ASSIGNED] = '50:assigned,80:resolved,90:closed';
$g_status_enum_workflow[RESOLVED] = '50:assigned,80:resolved,90:closed,85:delivered';
$g_status_enum_workflow['DELIVERED'] = '40:confirmed,45:monitored,87:tested;90:closed';
$g_status_enum_workflow['TESTED'] = '90:closed,40:confirmed,45:monitored';
$g_status_enum_workflow[CLOSED] = '40:confirmed,45:monitored';
$g_status_enum_string = '5:suspended,10:new,20:feedback,30:acknowledged,31:prioritizationwaiting,40:confirmed,45:monitored,50:assigned,51:preprojetaffecte,52:devisrealise,53:demandeachat,54:bondecommande,55:refuse,56:cloture,75:incorrect,78:tobeintegrated,80:resolved,83:qualified,85:delivered,87:tested,88:mepwaiting,89:testednok,90:closed';
$g_bug_readonly_status_threshold = CLOSED;
$g_update_bug_status_threshold = UPDATER;
$g_bug_assigned_status = NEW_;
#$g_allow_reporter_close = ON;
$g_view_summary_threshold = UPDATER;
$g_handle_bug_threshold = UPDATER;
$g_update_readonly_bug_threshold = DEVELOPER;
$g_reminder_receive_threshold = VIEWER;
# Status color additions
$g_max_file_size = 500000000;
$g_status_colors['new'] =  '#0096FF';
$g_status_colors['feedback'] =  '#CC3300';
$g_status_colors['confirmed'] = '#FF663C';
$g_status_colors['monitored'] = '#FF553C';
$g_status_colors['assigned'] = '#FF995A';
$g_status_colors['resolved'] = '#FFCC78';
$g_status_colors['delivered'] = '#FFFF96';
$g_status_colors['tested'] = '#CCFF99';
$g_status_colors['closed'] = '#00FF00';
$g_status_colors['qualified'] = '#8E3557';
$g_status_colors['suspended'] = '#E8E8E8';
$g_status_colors['incorrect'] = '#FF0000';
$g_status_colors['tobeintegrated'] = '#CCEEDD';
$g_status_colors['acknowledged'] = '#A48640';
$g_status_colors['mepwaiting'] = '#A1D152';
$g_status_colors['prioritizationwaiting'] = '#FDA7D0';
$g_status_colors['testednok'] = '#FF9821';
####################################
$g_status_colors['preprojetaffecte'] = '#F9FC4C';
$g_status_colors['devisrealise'] = '#47F9E6';
$g_status_colors['demandeachat'] = '#FA9B3C';
$g_status_colors['bondecommande'] = '#AC4CFC';
$g_status_colors['refuse'] = '#FA2020';
$g_status_colors['cloture'] = '#20FA23';
##################################
$g_priority_enum_string = '10:none,20:low,30:normal,40:high,50:urgent';
$g_severity_enum_string = '10:feature,20:trivial,50:minor,60:major,80:block';
$g_reproducibility_enum_string = '10:always,50:random,90:unable to reproduce,100:non applicable';
$g_access_levels_enum_string = '10:viewer,25:reporter,40:updater,55:developer,60:super developer,70:manager,90:administrator';
$g_default_timezone = "Europe/Paris";
$g_webservice_rest_enabled = ON;
?>
EOH
        destination = "secrets/config_inc.php"
        change_mode = "restart"
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
          interval = "60s"
          timeout  = "5s"
          port     = "http"
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
