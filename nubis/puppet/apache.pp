$mod_auth_openidc_version = "2.2.0"
$libcjose_version = "0.4.1"
$asg_route53_version = "v0.0.2-beta3"

class { 'nubis_apache':
  project_name => 'sso',
  port => 82,
}

# Add modules
class { 'apache::mod::rewrite': }
class { 'apache::mod::proxy': }
class { 'apache::mod::proxy_http': }
class { 'apache::mod::proxy_html': }
class { 'apache::mod::include': }

apache::mod { 'sed': }
apache::mod { 'macro': }

file { "/var/www/html/index.html":
  ensure  => present,
  owner   => 'root',
  group   => 'root',
  require => [
    Class['Nubis_apache'],
  ],
  source => 'puppet:///nubis/files/html/index.html',
}

file { "/var/www/html/top.shtml":
  ensure  => present,
  owner   => 'root',
  group   => 'root',
  require => [
    Class['Nubis_apache'],
  ],
  source => 'puppet:///nubis/files/html/top.shtml',
}

file { "/var/www/html/bottom.shtml":
  ensure  => present,
  owner   => 'root',
  group   => 'root',
  require => [
    Class['Nubis_apache'],
  ],
  source => 'puppet:///nubis/files/html/bottom.shtml',
}

apache::vhost { 'localhost':
    port               => 82,
    default_vhost      => false,
    docroot            => '/var/www/html',
    docroot_owner      => 'root',
    docroot_group      => 'root',
    setenvif           => [
      'X-Forwarded-Proto https HTTPS=on',
      'Remote_Addr 127\.0\.0\.1 internal',
    ],
    access_log_env_var => '!internal',
    access_log_format  => '%a %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"',
}

apache::vhost { $project_name:
    port               => 82,
    default_vhost      => true,
    docroot            => '/var/www/html',
    docroot_owner      => 'root',
    docroot_group      => 'root',
    block              => ['scm'],
    setenvif           => [
      'X-Forwarded-Proto https HTTPS=on',
      'Remote_Addr 127\.0\.0\.1 internal',
      'Remote_Addr ^10\. internal',
    ],
    access_log_env_var => '!internal',
    access_log_format  => '%a %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"',
    
    directories => [
      { 'path' => '/var/www/html',
        'provider' => 'directory',
        'options' => '+Includes',
      },
      { 'path' => '/',
        'provider' => 'location',
        'auth_type' => 'openid-connect',
	'require' => 'unmanaged',
	'custom_fragment' => '
	Use RequireAdminsOrUsers
	ExpiresActive Off',
      },
      {
        'path' => '/consul',
        'provider' => 'location',
	'require' => 'unmanaged',
	'custom_fragment' => '
    # We need to decompress, sed, then recompress
    AddOutputFilterByType INFLATE;Sed;DEFLATE text/html
    # Look for a string like
    # var consulHost = \'\'
    # In consuls webUI
    OutputSed "s/\(var *consulHost *= *\)\'\'/\1\'\/consul\'/"

    ProxyPass http://consul.service.consul:8500 disablereuse=on ttl=60
    ProxyPassReverse http://consul.service.consul:8500
',
      },
      {
        'path' => '/jenkins',
        'provider' => 'location',
	'require' => 'unmanaged',
        'custom_fragment' => '
    SetEnv proxy-nokeepalive 1
    ProxyPass http://jenkins.service.consul:8080/jenkins disablereuse=on ttl=60 keepalive=off timeout=10
    ProxyPassReverse http://jenkins.service.consul:8080/jenkins
',
      },
      {
        'path' => '/elasticsearch',
        'provider' => 'location',
	'require' => 'unmanaged',
	'custom_fragment' => '
    ProxyPass http://es.service.consul:8080 disablereuse=on ttl=60
    ProxyPassReverse http://es.service.consul:8080
',
      },
      {
        'path' => '/kibana',
        'provider' => 'location',
	'require' => 'unmanaged',
	'custom_fragment' => '
    ProxyPass http://localhost:5601 disablereuse=on ttl=60
    ProxyPassReverse http://localhost:5601
    OIDCPassClaimsAs none
',
      },
      {
        'path' => '/prometheus',
        'provider' => 'location',
	'require' => 'unmanaged',
	'custom_fragment' => '
    ProxyPass http://prometheus.service.consul:81/prometheus disablereuse=on ttl=60
    ProxyPassReverse http://prometheus.service.consul:81/prometheus
',
      },
      {
        'path' => '/alertmanager',
        'provider' => 'location',
	'require' => 'unmanaged',
	'custom_fragment' => '
    ProxyPass http://alertmanager.service.consul:9093/alertmanager disablereuse=on ttl=60
    ProxyPassReverse http://alertmanager.service.consul:9093/alertmanager
',
      },
      {
        'path' => '/grafana',
        'provider' => 'location',
	'require' => 'unmanaged',
	'custom_fragment' => '
    ProxyPass http://grafana.service.consul:3000 disablereuse=on ttl=60
    ProxyPassReverse http://grafana.service.consul:3000
',
      },
      { 
        'path' => '/sso',
        'provider' => 'location',
        'auth_type' => 'openid-connect',
         require => "valid-user",
      },
    ],
    custom_fragment    => "
# Clustered without coordination
FileETag None

OIDCProviderTokenEndpointAuth client_secret_post
OIDCScope 'openid name email profile'
OIDCCookiePath /

OIDCInfoHook userinfo
OIDCRemoteUserClaim email
OIDCOAuthTokenExpiryClaim exp absolute mandatory
OIDCPassIDTokenAs claims serialized
OIDCOAuthTokenIntrospectionInterval 15
OIDCUserInfoRefreshInterval 15
OIDCSessionMaxDuration 0
OIDCSessionInactivityTimeout 43200

ServerName sso.stage.us-west-2.nubis-gozer.nubis.allizom.org
",
    headers            => [
      "set X-SSO-Nubis-Version ${project_version}",
      "set X-SSO-Nubis-Project ${project_name}",
      "set X-SSO-Nubis-Build   ${packer_build_name}",
    ],
}


staging::file { '/usr/local/bin/asg-route53':
  source => "https://github.com/gozer/asg-route53/releases/download/${asg_route53_version}/asg-route53.${asg_route53_version}-linux_amd64",
  target => '/usr/local/bin/asg-route53',
}->
exec { 'chmod asg-route53':
  command => 'chmod 755 /usr/local/bin/asg-route53',
  path    => ['/usr/bin','/bin'],
}

# Install mod_auth_openidc and dependency
package { "libjansson4":
  ensure => installed,
}->
package { "libhiredis0.10":
  ensure => installed,
}->
package { "memcached":
  ensure => installed,
}->
staging::file { 'libcjose0.deb':
  source => "https://github.com/pingidentity/mod_auth_openidc/releases/download/v${mod_auth_openidc_version}/libcjose0_${libcjose_version}-1.${::lsbdistcodename}.1_${::architecture}.deb",
}->
package { "libcjose0":
  provider => dpkg,
  ensure => installed,
  source => '/opt/staging/libcjose0.deb'
}->
staging::file { 'mod_auth_openidc.deb':
  source => "https://github.com/pingidentity/mod_auth_openidc/releases/download/v${mod_auth_openidc_version}/libapache2-mod-auth-openidc_${mod_auth_openidc_version}-1.${::lsbdistcodename}.1_${::architecture}.deb",
}->
package { "mod_auth_openidc":
  provider => dpkg,
  ensure => installed,
  source => '/opt/staging/mod_auth_openidc.deb',
  require => [
    Class['Nubis_apache'],
  ]
}->
apache::mod { 'auth_openidc': }
