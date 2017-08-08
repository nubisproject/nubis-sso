# Enable consul-template, base doesn't enable it yet
class { 'consul_template':
    service_enable => true,
    service_ensure => 'stopped',
    version        => '0.16.0',
    user           => 'root',
    group          => 'root',
}

# Drop our template
file { "${consul_template::config_dir}/top.shtml.ctmpl":
  ensure  => file,
  owner   => root,
  group   => root,
  mode    => '0644',
  source  => 'puppet:///nubis/files/html/top.shtml.ctmpl',
  require => [
    Class['consul_template'],
  ],
}

file { "${consul_template::config_dir}/admin.conf.ctmpl":
  ensure  => file,
  owner   => root,
  group   => root,
  mode    => '0644',
  source  => 'puppet:///nubis/files/admin.conf.ctmpl',
  require => [
    Class['consul_template'],
  ],
}

# Configure our navigation links
consul_template::watch { 'top.shtml':
    source      => "${consul_template::config_dir}/top.shtml.ctmpl",
    destination => '/var/www/html/top.shtml',
    command     => '/bin/true',
}

# Configure Apache Proxy
consul_template::watch { 'admin.conf':
    source      => "${consul_template::config_dir}/admin.conf.ctmpl",
    destination => '/etc/apache2/conf.d/admin.conf',
    command     => '/etc/init.d/apache2 reload || /etc/init.d/apache2 restart',
}
