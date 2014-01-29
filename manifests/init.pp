# == Class: webapp
#
# Manage webapp
#
class webapp (
  $serveradmin     = "webmaster@${::domain}",
  $apache_log_path = '/var/log/httpd',
) {

  include apache
  include common
  include common::deploy_dir
  include deployment

  # validate apache_log_path
  # used in apache vhost for webapp::instance
  validate_absolute_path($apache_log_path)

  # create resources for all the webapp app's defined in hiera.
  $webapp_instances = hiera_hash('webapp_instances', undef)
  create_resources('webapp::instance', $webapp_instances)

  # Generate a list of all the app names on the server
  if $webapp_instances {
    $app_names = unique(keys($webapp_instances))
    webapp::app { $app_names: }
  }

}
