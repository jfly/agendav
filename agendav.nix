{
  fetchurl,
  lib,
  php,
  stdenv,
  symlinkJoin,
  writeShellApplication,
  writeText,
  nginx,
  runCommand,
}:

let
  version = "2.6.0";
  #<<< runtimeDir = "/run/agendav-phpfpm";
  runtimeDir = "/tmp/agendav-phpfpm"; #<<<
  agendavSrc = stdenv.mkDerivation {
    name = "agendav";
    src = fetchurl {
      url = "https://github.com/agendav/agendav/releases/download/${version}/agendav-${version}.tar.gz";
      sha256 = "sha256-r3LAeIbjDSRDzpWHmS9Zx4+tWrSgaeMRKG4echbbiV4=";
    };
    patches = [
      ./use-error-logging-instead.patch
    ];

    installPhase = ''
      mkdir $out
      cp -r . $out
    '';
  };
  # Full list of settings: https://agendav.readthedocs.io/en/latest/admin/configuration/
  settings = writeText "settings.php" ''
    <?php
    // Site title
    $app['site.title'] = 'manmancal';

    $app['db.options'] = [
      'path' => '${runtimeDir}/db.sqlite',
      'driver' => 'pdo_sqlite',
    ];

    $app['twig.options'] = array('cache' => '${runtimeDir}/twig-cache');

    $app['caldav.baseurl'] = 'http://localhost:5232/';
  '';
  agendaSrcWithSettings = runCommand "agendav-src-with-settings" {} ''
    cp -r ${agendavSrc} $out
    chmod +w -R $out
    cp ${settings} $out/web/config/settings.php
  '';

  fpmListenSock = "${runtimeDir}/www.sock";
  myPhp = php.buildEnv {
    extraConfig = ''
      date.timezone = "America/Los_Angeles"
      log_errors = yes
      error_log = "/dev/stderr"
    '';
  };

  # Bare minimum php fpm config cobbled together from
  # https://nixos.wiki/wiki/Phpfpm and
  # nixos/modules/services/web-servers/phpfpm/default.nix in nixpkgs.
  fpmCfgFile = writeText "phpfpm.conf" ''
    [global]
    error_log = "/dev/stderr"
    daemonize = no

    [www]
    listen = ${fpmListenSock}
    pm = "dynamic"
    pm.max_children = 4
    pm.start_servers = 2
    pm.min_spare_servers = 2
    pm.max_spare_servers = 4
    catch_workers_output = yes
  '';

  nginxConf = writeText "nginx.conf" ''
    daemon off;
    error_log /dev/stdout info;

    events {}

    http {
      include    ${nginx}/conf/mime.types;
      access_log /dev/stdout;

      server {
        listen       8081;
        root         ${agendaSrcWithSettings}/web/public;

        access_log /var/log/nginx/example.journaldev.com-access.log;
        error_log  /var/log/nginx/example.journaldev.com-error.log error;
        index index.html index.htm index.php;

        location / {
          try_files $uri $uri/ /index.php$is_args$args;
        }

        location ~ \.php$ {
          fastcgi_split_path_info ^(.+\.php)(/.+)$;
          fastcgi_pass unix:${fpmListenSock};
          fastcgi_index index.php;
          include ${nginx}/conf/fastcgi.conf;
        }
      }
    }
  '';

in

rec {
  php = writeShellApplication {
    name = "agendav-php";
    text = ''
      rm -r ${runtimeDir}
      mkdir -p ${runtimeDir}

      touch ${runtimeDir}/db.sqlite #<<< DRY >>>
      (
        cd ${agendaSrcWithSettings}
        ${myPhp}/bin/php agendavcli migrations:migrate -q
      )

      exec ${myPhp}/bin/php-fpm -y ${fpmCfgFile}
    '';
  };
  nginx = writeShellApplication {
    name = "agendav-nginx";
    text = ''
      exec ${nginx}/bin/nginx -e /dev/stderr -c ${nginxConf}
    '';
  };
  all = writeShellApplication {
    name = "agendav";
    text = ''
      ${concurrently} ${php} ${nginx}
    '';
  };
};
