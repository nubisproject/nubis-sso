# bootup actions
file { '/etc/nubis.d/sso':
    ensure => file,
    owner  => root,
    group  => root,
    mode   => '0755',
    source => 'puppet:///nubis/files/startup',
}
