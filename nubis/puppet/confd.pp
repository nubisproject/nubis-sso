file { '/etc/confd':
  ensure  => directory,
  recurse => true,
  purge   => false,
  owner   => 'root',
  group   => 'root',
  source  => 'puppet:///nubis/files/confd',
}

file { '/usr/local/bin/nubis-sso-generated':
  ensure => 'present',
  mode   => '0755',
  owner  => 'root',
  group  => 'root',
  source => 'puppet:///nubis/files/generated',
}

file { '/etc/apache2/conf.d/sso-require-macros.conf':
  ensure  => 'present',
  mode    => '0644',
  owner   => 'root',
  group   => 'root',
  content => '<Macro RequireAdminsOrUsers></Macro>',
}
