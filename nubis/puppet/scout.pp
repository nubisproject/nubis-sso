python::pip { 'AWSScout2':
  ensure =>  '3.0.3'
}

file { '/usr/local/bin/run-scout':
  ensure  => file,
  owner   => root,
  group   => root,
  mode    => '0755',
  source  =>  'puppet:///nubis/files/run-scout',
  require => Python::Pip['AWSScout2'],
}

# This needs to be here so that we can run scout once
file { '/etc/nubis.d/999-run-scout':
  ensure  => link,
  target  => '/usr/local/bin/run-scout',
  require => File['/usr/local/bin/run-scout'],
}

file { '/etc/cron.daily/run-scout':
  ensure  => link,
  target  => '/usr/local/bin/run-scout',
  require =>  File['/usr/local/bin/run-scout'],
}

