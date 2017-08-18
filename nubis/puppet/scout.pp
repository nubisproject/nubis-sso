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
file { '/etc/nubis.d/zzz-run-scout':
  ensure  => link,
  target  => '/usr/local/bin/run-scout',
  require => File['/usr/local/bin/run-scout'],
}

# Run scout once a day
file { '/etc/cron.daily/run-scout':
  ensure  => link,
  target  => '/usr/local/bin/run-scout',
  require =>  File['/usr/local/bin/run-scout'],
}

