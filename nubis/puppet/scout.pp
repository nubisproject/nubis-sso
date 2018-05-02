python::pip { 'AWSScout2':
  ensure =>  '3.0.3'
}

file { '/var/www/html/scout':
  ensure  => directory,
  owner   => 'root',
  group   => 'root',
  require => [
    Class['nubis_apache'],
  ],
}

file { '/var/www/html/scout/index.html':
  ensure  => link,
  target  => 'report.html',
  require => [
    File['/var/www/html/scout'],
  ],
}

# Dummy placeholder until real report exists
file { '/var/www/html/scout/report.html':
  ensure  => 'present',
  mode    => '0644',
  owner   => 'root',
  group   => 'root',
  require => [
    File['/var/www/html/scout'],
  ],
  content => @(EOF),
  Security report not generated yet, check again tomorrow
EOF
}

file { '/usr/local/bin/run-scout':
  ensure  => file,
  owner   => root,
  group   => root,
  mode    => '0755',
  source  =>  'puppet:///nubis/files/run-scout',
  require => Python::Pip['AWSScout2'],
}

file { '/usr/local/bin/nubis-scout-ruleset.json':
  ensure  => file,
  owner   => root,
  group   => root,
  mode    => '0644',
  source  => 'puppet:///nubis/files/nubis-scout-ruleset.json',
  require =>  File['/usr/local/bin/run-scout'],
}

# This needs to be here so that we can run scout once
cron { 'run-scout-startup':
  ensure  => 'present',
  special => 'reboot',
  command => 'nubis-cron run-scout /usr/local/bin/run-scout',
}

# Run scout once a day
cron::daily { 'run-scout':
  ensure  => present,
  user    =>  'root',
  command => 'nubis-cron run-scout /usr/local/bin/run-scout',
}

