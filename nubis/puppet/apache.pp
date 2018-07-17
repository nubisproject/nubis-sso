$mod_auth_openidc_version = '2.3.0'
$libcjose_version = '0.5.1'
$asg_route53_version = 'v0.0.2-beta3'

class { 'nubis_apache':
  project_name    => 'sso',
  port            => 82,
  mpm_module_type => 'prefork',
}

# Add modules
class { 'apache::mod::rewrite': }
class { 'apache::mod::proxy': }
class { 'apache::mod::proxy_http': }
class { 'apache::mod::proxy_html': }
class { 'apache::mod::include': }
class { 'apache::mod::ssl': }

apache::mod { 'sed': }
apache::mod { 'macro': }

file { '/var/www/html/favicon.ico':
  ensure  => present,
  owner   => 'root',
  group   => 'root',
  require => [
    Class['Nubis_apache'],
  ],
  source  => 'puppet:///nubis/files/html/favicon.ico',
}

file { '/var/www/html/index.html':
  ensure  => present,
  owner   => 'root',
  group   => 'root',
  require => [
    Class['Nubis_apache'],
  ],
  source  => 'puppet:///nubis/files/html/index.html',
}

file { '/var/www/html/bottom.shtml':
  ensure  => present,
  owner   => 'root',
  group   => 'root',
  require => [
    Class['Nubis_apache'],
  ],
  source  => 'puppet:///nubis/files/html/bottom.shtml',
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
    directories        => [
      {
        'path'     => '/var/www/html',
        'provider' => 'directory',
        'require'  => 'local',
      },
    ],
}

apache::vhost { $project_name:
    port                        => 82,
    default_vhost               => true,
    docroot                     => '/var/www/html',
    docroot_owner               => 'root',
    docroot_group               => 'root',
    block                       => ['scm'],

    ssl_proxyengine             => true,
    ssl_proxy_verify            => 'none',
    ssl_proxy_check_peer_cn     => 'off',
    ssl_proxy_check_peer_name   => 'off',
    ssl_proxy_check_peer_expire => 'off',

    setenvif                    => [
      'X-Forwarded-Proto https HTTPS=on',
      'Remote_Addr 127\.0\.0\.1 internal',
      'Remote_Addr ^10\. internal',
    ],

    # Create 2 canonical outging HTTP headers with Username and the groups they belong to
    request_headers             => [
      'set X-Nubis-SSO-Username "%{OIDC_CLAIM_email}e"',
      'set X-Nubis-SSO-Groups "%{OIDC_CLAIM_https---sso.mozilla.com-claim-groups}e"',
    ],

    access_log_env_var          => '!internal',
    access_log_format           => '%a %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"',

    aliases                     => [
      {
        'scriptalias' => '/aws',
        'path'        => '/var/www/html/aws.py',
      },
      {
        'scriptalias' => '/rbac-not-authorized',
        'path'        => '/var/www/html/rbac-not-authorized',
      },
    ],

    directories                 => [
      {
        'path'     => '/var/www/html',
        'provider' => 'directory',
        'options'  => '+Includes',
      },
      {
        'path'            => '/',
        'provider'        => 'location',
        'auth_type'       => 'openid-connect',
        'require'         => 'unmanaged',
        'custom_fragment' => '
	ErrorDocument 401 "/rbac-not-authorized?reason=you+do+not+have+access+to+this+account"
	Use RequireEverybody
	ExpiresActive Off',
      },
      {
        'path'            => '/consul',
        'provider'        => 'location',
        'require'         => 'unmanaged',
        'custom_fragment' => '
    # We need to decompress, sed, then recompress
    AddOutputFilterByType INFLATE;Sed;DEFLATE text/html
    # Look for a string like
    # var consulHost = \'\'
    # In consuls webUI
    OutputSed "s/\(var *consulHost *= *\)\'\'/\1\'\/consul\'/"
    
    Use RBAC_Consul

    ProxyPass http://consul.service.consul:8500 disablereuse=on ttl=60
    ProxyPassReverse http://consul.service.consul:8500
',
      },
      {
        'path'            => '/jenkins',
        'provider'        => 'location',
        'require'         => 'unmanaged',
        'custom_fragment' => '

    Use RBAC_Jenkins

    SetEnv proxy-nokeepalive 1
    ProxyPass http://jenkins.service.consul:8080/jenkins disablereuse=on ttl=60 keepalive=off timeout=10
    ProxyPassReverse http://jenkins.service.consul:8080/jenkins
',
      },
      {
        'path'            => '/kubernetes',
        'provider'        => 'location',
        'require'         => 'unmanaged',
        'custom_fragment' => '

    Use RBAC_Kubernetes

    ProxyPass https://kubernetes.service.consul:31443 disablereuse=on ttl=60
    ProxyPassReverse https://kubernetes.service.consul:31443
',
      },
      {
        'path'            => '/elasticsearch',
        'provider'        => 'location',
        'require'         => 'unmanaged',
        'custom_fragment' => '
    Use RBAC_Elasticsearch

    ProxyPass http://es.service.consul:8080 disablereuse=on ttl=60
    ProxyPassReverse http://es.service.consul:8080
',
      },
      {
        'path'            => '/kibana',
        'provider'        => 'location',
        'require'         => 'unmanaged',
        'custom_fragment' => '
    Use RBAC_Kibana

    ProxyPass http://localhost:5601 disablereuse=on ttl=60
    ProxyPassReverse http://localhost:5601
    OIDCPassClaimsAs none
',
      },
      {
        'path'            => '/aws',
        'provider'        => 'location',
        'require'         => 'unmanaged',
        'custom_fragment' => '
    Use RBAC_AWS
',
      },
      {
        'path'            => '/scout',
        'provider'        => 'location',
        'require'         => 'unmanaged',
        'custom_fragment' => '
    Use RBAC_Scout
',
      },
      {
        'path'            => '/prometheus',
        'provider'        => 'location',
        'require'         => 'unmanaged',
        'custom_fragment' => '
    Use RBAC_Prometheus

    ProxyPass http://prometheus.service.consul:81/prometheus disablereuse=on ttl=60
    ProxyPassReverse http://prometheus.service.consul:81/prometheus
',
      },
      {
        'path'            => '/alertmanager',
        'provider'        => 'location',
        'require'         => 'unmanaged',
        'custom_fragment' => '
    Use RBAC_Alertmanager

    ProxyPass http://alertmanager.service.consul:9093/alertmanager disablereuse=on ttl=60
    ProxyPassReverse http://alertmanager.service.consul:9093/alertmanager
',
      },
      {
        'path'            => '/grafana',
        'provider'        => 'location',
        'require'         => 'unmanaged',
        'custom_fragment' => '
    Use RBAC_Grafana

    ProxyPass http://grafana.service.consul:3000 disablereuse=on ttl=60
    ProxyPassReverse http://grafana.service.consul:3000
',
      },
      {
        'path'      => '/sso',
        'provider'  => 'location',
        'auth_type' => 'openid-connect',
        require     => 'valid-user',
      },
    ],
    custom_fragment             => "
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
",
    headers                     => [
      "set X-Nubis-Version ${project_version}",
      "set X-Nubis-Project ${project_name}",
      "set X-Nubis-Build   ${packer_build_name}",
    ],
}

staging::file { '/usr/local/bin/asg-route53':
  source => "https://github.com/gozer/asg-route53/releases/download/${asg_route53_version}/asg-route53.${asg_route53_version}-linux_amd64",
  target => '/usr/local/bin/asg-route53',
}
->exec { 'chmod asg-route53':
  command => 'chmod 755 /usr/local/bin/asg-route53',
  path    => ['/usr/bin','/bin'],
}

# Install mod_auth_openidc and dependency
package { 'libjansson4':
  ensure => '2.7-*',
}
->package { 'libhiredis0.13':
  ensure => '0.13.3-*',
}
->package { 'memcached':
  ensure => '1.4.25-*',
}
->package { 'libcurl3':
  ensure => '7.47.0-*',
}
->staging::file { 'libcjose0.deb':
  source => "https://github.com/pingidentity/mod_auth_openidc/releases/download/v2.3.0/libcjose0_${libcjose_version}-1.wily.1_${::architecture}.deb",
}
->package { 'libcjose0':
  ensure   => installed,
  provider => dpkg,
  source   => '/opt/staging/libcjose0.deb'
}
->staging::file { 'mod_auth_openidc.deb':
  source => "https://github.com/pingidentity/mod_auth_openidc/releases/download/v${mod_auth_openidc_version}/libapache2-mod-auth-openidc_${mod_auth_openidc_version}-1.wily.1_${::architecture}.deb",
}
->package { 'mod_auth_openidc':
  ensure   => installed,
  provider => dpkg,
  source   => '/opt/staging/mod_auth_openidc.deb',
}
->apache::mod { 'auth_openidc': }

python::pip { 'boto':
  ensure =>  '2.48.0'
}

# For our custom error page
package { 'libcgi-pm-perl':
  ensure => 'latest',
}

file { '/var/www/.aws':
  ensure  => directory,
  owner   => $::apache::params::user,
  group   => $::apache::params::group,
  require => [
    Class['nubis_apache'],
  ]
}

file { '/var/www/html/aws.py':
  ensure  => present,
  owner   => 'root',
  group   => 'root',
  mode    => '0755',
  require => [
    Class['Nubis_apache'],
  ],
  source  => 'puppet:///nubis/files/aws',
}

file { '/var/www/html/rbac-not-authorized':
  ensure  => present,
  owner   => 'root',
  group   => 'root',
  mode    => '0755',
  require => [
    Class['Nubis_apache'],
    Package['libcgi-pm-perl'],
  ],
  source  => 'puppet:///nubis/files/error',
}
