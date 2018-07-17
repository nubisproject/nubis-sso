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

# Just for syntax checks, overriden later
file { '/etc/apache2/conf.d/sso-require-macros.conf':
  ensure  => 'present',
  mode    => '0644',
  owner   => 'root',
  group   => 'root',
  content => @(EOF),
  <Macro RequireEverybody></Macro>
  <Macro RequireOpers></Macro>
  <Macro RequireUsers></Macro>
  <Macro RBAC_Consul></Macro>
  <Macro RBAC_Scout></Macro>
  <Macro RBAC_Jenkins></Macro>
  <Macro RBAC_Elasticsearch></Macro>
  <Macro RBAC_Kibana></Macro>
  <Macro RBAC_AWS></Macro>
  <Macro RBAC_Prometheus></Macro>
  <Macro RBAC_Alertmanager></Macro>
  <Macro RBAC_Grafana></Macro>
EOF
}
