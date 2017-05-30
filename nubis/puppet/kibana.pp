class { 'kibana':
  package_repo_version => '5.1',
  version              => '5.1.2',
  config               => {
    'elasticsearch.url' => 'http://es.service.consul:8080',
    'server.basePath'   => '/kibana',
    'logging.quiet'     => true,
  },
}

# Fix dependency chains for apt update
Apt::Source['kibana'] -> Class['apt::update'] -> Package['kibana']

# Enable Kibana init-v service on boot
exec { 'update-rc.d kibana defaults':
  command => '/usr/sbin/update-rc.d kibana defaults',
  require => [
    Package['kibana'],
  ],
}
