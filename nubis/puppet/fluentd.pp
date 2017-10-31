fluentd::configfile { 'traefik': }

fluentd::source { 'traefik':
  configfile  => 'traefik',
  type        => 'tail',
  format      => 'json',
  time_format => '%Y-%m-%dT%H:%M:%SZ',
  tag         => 'forward.traefik.access',
  config      => {
    'path'     => '/var/log/traefik.log',
    'pos_file' => '/var/log/traefik.log.pos',
  },
}
