$mod_auth_openidc_version = "2.2.0"
$libcjose_version = "0.4.1"

class { 'nubis_apache':
  port => 82,
}

# Add modules
class { 'apache::mod::rewrite': }
class { 'apache::mod::proxy': }
class { 'apache::mod::proxy_http': }
class { 'apache::mod::proxy_html': }

file { "/var/www/html/index.html":
  ensure => present,
  require => [
    Class['Nubis_apache'],
  ],
  content => "Hello world!"
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
      { 'path' => '/',
        'provider' => 'location',
	'require' => 'unmanaged',
	'expires_active' => false,
      },
      {
        'path' => '/prometheus',
        'provider' => 'location',
        'auth_type' => 'openid-connect',
         require => {
          enforce  => 'all',
          requires => [
            'claim multifactor:duo',
            'claim groups:nubis_global_admins',
          ],
	},
	'custom_fragment' => '
    ProxyPass http://prometheus.service.consul:81/prometheus
    ProxyPassReverse http://prometheus.service.consul:81/prometheus
',
      },
      {
        'path' => '/alertmanager',
        'provider' => 'location',
        'auth_type' => 'openid-connect',
         require => {
          enforce  => 'all',
          requires => [
            'claim multifactor:duo',
            'claim groups:nubis_global_admins',
          ],
	},
	'custom_fragment' => '
    ProxyPass http://alertmanager.service.consul:9093/alertmanager
    ProxyPassReverse http://alertmanager.service.consul:9093/alertmanager
',
      },
      {
        'path' => '/grafana',
        'provider' => 'location',
        'auth_type' => 'openid-connect',
         require => {
          enforce  => 'all',
          requires => [
            'claim multifactor:duo',
            'claim groups:nubis_global_admins',
          ],
	},
	'custom_fragment' => '
    ProxyPass http://grafana.service.consul:3000
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

ServerName sso.stage.us-west-2.nubis-gozer.nubis.allizom.org
",
    headers            => [
      "set X-SSO-Nubis-Version ${project_version}",
      "set X-SSO-Nubis-Project ${project_name}",
      "set X-SSO-Nubis-Build   ${packer_build_name}",
    ],
    #rewrites           => [
    #  {
    #    comment      => 'HTTPS redirect',
    #    rewrite_cond => ['%{HTTP:X-Forwarded-Proto} =http'],
    #    rewrite_rule => ['. https://%{HTTP:Host}%{REQUEST_URI} [L,R=permanent]'],
    #  }
    #]
}


staging::file { '/usr/local/bin/asg-route53':
  source => "https://github.com/gozer/asg-route53/releases/download/v0.0.2-beta2/asg-route53.v0.0.2-beta2-linux_amd64",
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
