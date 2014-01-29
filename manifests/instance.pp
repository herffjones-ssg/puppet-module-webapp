# == Define: webapp
#
# PHP Application with configuration gathered from Hiera
#
define webapp::instance (
  $interface = undef,
){
  # Set the app name to the name of what called this.
  $app_name = $name

  # For PHP, the instance and the app are the same thing
  $instancename = $app_name

  # Hash of config entries for app
  $config = hiera_hash("${app_name}::config")

  if $interface {
    $real_interface = $interface
  } else {
    if has_interface_with("bond0:0") {
      $real_interface = "bond0:0"
    } elsif has_interface_with("eth0") {
      $real_interface = "eth0"
    } elsif has_interface_with("eth1") {
      $real_interface = "eth1"
    } elsif has_interface_with("bond0") {
      $real_interface = "bond0"
    } else {
      fail("Unable to find interface")
    }
  }

  # formats interface to be passed on to a template to retrieve the fact.
  # Example: int_to_fact('bond0:0') returns 'ipaddress_bond0_0'.
  $listen_ip_fact = int_to_fact($real_interface)

  if $config['approved'] == true {

    # The apache template to use
    $vhost_template = $config['vhost_template']
    if ! $vhost_template {
      $real_vhost_template = "webapp/default-vhost.conf.erb"
    } else {
      $real_vhost_template = "${vhost_template}"
    }

    # Allow us to define classes from hiera config
    $required_classes = $config['required_classes']
    if $required_classes {
       include $required_classes
    }

    # Allow us to define packages from hiera config
    $required_packages = $config['required_packages']
    if $required_packages {
       ensure_packages($required_packages)
    }

    # Allow us to define resources from hiera config
    $required_resources = $config['required_resources']
    if $required_resources {
       make_resources($required_resources)
    }

    $deploy_dir = $config['deploy_dir']
    if $deploy_dir {
      $real_deploy_dir = "$deploy_dir"
    } else {
      $real_deploy_dir = "/x01/www/html/$instancename"
    }

    file { "$real_deploy_dir":
      ensure => directory,
      owner  => 'apache',
      group  => 'apache',
      mode   => '0775',
    }

    $servername    = $config['servername']
    $serveraliases = $config['serveraliases']
    $rewrite_rules = $config['coldfusion_rewrite_rules']
    $extra_apache_config = $config['extra_apache_config']

    # Nagios Config
    $health_page = $config['health_custom_page']
    if ! $health_page {
      $real_health_page = "/health/"
    } else {
      $real_health_page = $health_page
    }

    $health_text = $config['health_custom_text']
    if ! $health_text {
      $real_health_text = "SUCCESS"
    } else {
      $real_health_text = $health_text
    }

    $contact_groups = $config['contact_groups']
    if ! $contact_groups {
      if $::env == "dev" or $::env == "test" {
        $real_contact_groups = "indywebemail"
      } else {
        $real_contact_groups = "indyweb"
      }
    } else {
      $real_contact_groups = $contact_groups
    }

    $check_period = $config['check_period']
    if ! $check_period {
      if $::env == "dev" or $::env == "test" {
        $real_check_period = "workhours_indy"
      } else {
        $real_check_period = "24x7"
      }
    } else {
      $real_check_period = $check_period
    }

    $normal_check_interval = $config['normal_check_interval']
    if ! $normal_check_interval {
      if $::env == "dev" or $::env == "test" {
        $real_normal_check_interval = "5"
      } else {
        $real_normal_check_interval = "5"
      }
    } else {
      $real_normal_check_interval = $normal_check_interval
    }

    $notification_interval = $config['notification_interval']
    if ! $notification_interval {
      if $::env == "dev" or $::env == "test" {
        $real_notification_interval = "90"
      } else {
        $real_notification_interval = "30"
      }
    } else {
      $real_notification_interval = $notification_interval
    }

    $first_notification_delay = $config['first_notification_delay']
    if ! $first_notification_delay {
      if $::env == "dev" or $::env == "test" {
        $real_first_notification_delay = "90"
      } else {
        $real_first_notification_delay = "5"
      }
    } else {
      $real_first_notification_delay = $first_notification_delay
    }

    $notification_period = $config['notification_period']
    if ! $notification_period {
      if $::env == "dev" or $::env == "test" {
        $real_notification_period = "workhours_indy"
      } else {
        $real_notification_period = "24x7"
      }
    } else {
      $real_notification_period = $notification_period
    }

    $event_handler = $config['event_handler']
    if ! $event_handler {
      $real_event_handler = "servicebounce!httpd"
    } else {
      if $event_handler == "none" {
        $real_event_handler = ""
      }
    }

   $listen_ip = getvar($listen_ip_fact)

   @@nagios_service { "${instancename}${hostname}":
      ensure              => present,
      use                 => "generic-service",
      host_name           => $hostname,
      service_description => "HTTP_${instancename} on ${fqdn}",
      check_command       => "hj_ae_check_http_generic!${::env}!${app_name}!-w 5!-c 10!-H ${servername}!-I ${listen_ip}!-p 80!-u ${health_page}!--onredirect=sticky!--string=\'${health_text}\'",
      contact_groups      => $real_contact_groups,
      event_handler       => $real_event_handler,
      first_notification_delay   => $real_first_notification_delay,
      check_period        => $real_check_period,
      notification_period => $real_notification_period,
      normal_check_interval   => $real_normal_check_interval,
      notification_interval   => $real_notification_interval,
      target              => "/etc/nagios/websites/${servername}.cfg",
   }

    # Document root subfolder.  Will be after the /x01/www/html/instancename
    $sub_path = $config['sub_path']

    $cleaned_name = clean_name($instancename)
    $server_default_alias = "${cleaned_name}${::fqdn}"

    # used in vhost template
    $serveradmin = $config['serveradmin'] ? {
      undef   => "ssgwebteam@herffjones.com",
      default => $config['serveradmin'],
    }

    emailrequest::dns { "DNS for $server_default_alias":
      hostname     => $server_default_alias,
      ip           => getvar($listen_ip_fact),
    }

    # Ugly hack to allow apache to read it's own log files
    # Should be removed once a real log collection tool is in place
    if $config['apache_log_access'] == true {
      file { "apache_log_dir_${instancename}":
        ensure => directory,
        path   => "/var/log/httpd",
        mode   => '0755',
      }
    }

    file { "${instancename}_apache_vhost":
      ensure  => file,
      path    => "/etc/httpd/conf.d/${instancename}.conf",
      content => template($real_vhost_template),
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      notify  => Service['httpd'],
    }

  }

}
