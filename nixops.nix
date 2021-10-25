{
  randomcat-server =
    { config, pkgs, modulesPath, ... }:
    {
      deployment.targetHost = "51.222.27.55";

      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
        ./modules/system-types/basic-ovh.nix
        ./modules/wants/ssh-access.nix
        ./modules/wants/local-root-access.nix
        ./modules/wants/agorabot.nix
        ./modules/wants/agorabot-server.nix
      ];

      services.randomcat.agorabot-server = {
        enable = true;
        user = "discord-bot";
      };

      nix.gc.automatic = true;
      nix.optimise.automatic = true;

      users.users.discord-bot = {
        group = "discord-bot";
      };

      users.groups.discord-bot = {
        members = [ "discord-bot" ];
      };

      services.randomcat.agorabot-server.instances = {
        "agora-prod" = {
          package = import (builtins.fetchGit {
            url = "https://github.com/randomnetcat/AgoraBot.git";
            ref = "main";
            rev = "bf32b479e7db77799cf2ff6548256b880c9b7a53";
          }) { inherit (pkgs); };

          token = builtins.readFile ./secrets/discord/agora-prod-token;

          configSource = ./public-config/agorabot/agora-prod;

          secretConfigFiles = {
            "digest/ssmtp.conf" = {
              text = builtins.readFile ./secrets/discord/agora-prod-ssmtp-config;
            };
          };

          extraConfigFiles = {
            "digest/mail.json" = {
              text = ''
                {
                  "send_strategy": "ssmtp",
                  "ssmtp_path": "${pkgs.ssmtp}/bin/ssmtp",
                  "ssmtp_config_path": "ssmtp.conf"
                }
              '';
            };
          };

          dataVersion = 1;
        };

        "secret-hitler" = {
          package = import (builtins.fetchGit {
            url = "https://github.com/randomnetcat/AgoraBot.git";
            ref = "secret-hitler";
            rev = "a45cb180d06cd2d0cbb91c884d463af99cb1fa61";
          }) { inherit (pkgs); };

          token = builtins.readFile ./secrets/discord/secret-hitler-token;

          configSource = ./public-config/agorabot/secret-hitler;
          dataVersion = 1;
        };
      };

      deployment.keys =
        let
          postgresPw = builtins.readFile ./secrets/zulip/agora/postgres_pw;
          memcachedPw = builtins.readFile ./secrets/zulip/agora/memcached_pw;
          rabbitmqPw = builtins.readFile ./secrets/zulip/agora/rabbitmq_pw;
          redisPw = builtins.readFile ./secrets/zulip/agora/redis_pw;
          zulipSecretKey = builtins.readFile ./secrets/zulip/agora/secret_key;
        in
          {
            zulip-postgres-env = {
              text = ''
                POSTGRES_DB=zulip
                POSTGRES_USER=zulip
                POSTGRES_PASSWORD=${postgresPw}
              '';
            };

            zulip-memcached-env = {
              text = ''
                SASL_CONF_PATH=/home/memcache/memcached.conf
                MEMCACHED_SASL_PWDB=/home/memcache/memcached-sasl-db
                MEMCACHED_PASSWORD=${memcachedPw}
              '';
            };

            zulip-rabbitmq-env = {
              text = ''
                RABBITMQ_DEFAULT_USER=zulip
                RABBIT_MQ_DEFAULT_PASS=${rabbitmqPw}
              '';
            };

            zulip-redis-env = {
              text = ''
                REDIS_PASSWORD=${redisPw}
              '';
            };

            zulip-zulip-env = {
              text = ''
                DB_HOST=zulip-database
                DB_HOST_PORT=5432
                DB_USER=zulip
                SSL_CERTIFICATE_GENERATION=certbot
                SETTING_MEMCACHED_LOCATION=zulip-memcached
                SETTING_RABBITMQ_HOST=zulip-rabbitmq
                SETTING_REDIS_HOST=zulip-redis
                SERETS_email_password=123456789
                SECRETS_rabbitmq_password=${rabbitmqPw}
                SECRETS_postgres_password=${postgresPw}
                SECRETS_memcachd_password=${memcachedPw}
                SECRETS_redis_password=${redisPw}
                SECRETS_secret_key=${zulipSecretKey}
                SETTING_EXTERNAL_HOST=agora-zulip.randomcat.org
                SETTING_ZULIP_ADMINISTRATOR=admin@randomcat.org
                SETTING_EMAIL_HOST=
                SETTING_EMAIL_HOST_USER=noreply@agora-zulip.randomcat.org
                SETTING_EMAIL_PORT=587
                SETTING_EMAIL_USE_SSL=False
                SETTING_EMAIL_USE_TLS=True
                ZULIP_AUTH_BACKENDS=EmailAuthBackend
              '';
            };
          };

      systemd.services.init-zulip-agora-network-and-files = {
        description = "Create the network bridge zulip-agora-br for zulip.";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig.Type = "oneshot";

        script =
          let
            dockercli = "${config.virtualisation.docker.package}/bin/docker";
          in ''
             # Put a true at the end to prevent getting non-zero return code, which will
             # crash the whole service.
             check=$(${dockercli} network ls | grep "zulip-agora-br" || true)
             if [ -z "$check" ]; then
               ${dockercli} network create zulip-agora-br
             else
               echo "zulip-agora-br already exists in docker"
             fi
           '';
      };

      networking.firewall.allowedTCPPorts = [ 80 443 ];

      virtualisation.oci-containers.containers = {
        "zulip-database" = {
          image = "zulip/zulip-postgresql:10";
          environmentFiles = [ "/run/keys/zulip-postgres-env" ];
          volumes = [ "/opt/docker/zulip/postgresql/data:/var/lib/postgresql/data:rw" ];
          extraOptions = [ "--network=zulip-agora-br" ];
        };

        "zulip-memcached" = {
          image = "memcached:alpine";
          environmentFiles = [ "/run/keys/zulip-memcached-env" ];
          cmd = [
            "sh"
            "-euc"
            ''
              echo 'mech_list: plain' > "$SASL_CONF_PATH"
              echo "zulip@$HOSTNAME:$MEMCACHED_PASSWORD" > "$MEMCACHED_SASL_PWDB"
              echo "zulip@localhost:$MEMCACHED_PASSWORD" >> "$MEMCACHED_SASL_PWDB"
              exec memcached -S
            ''
          ];
          extraOptions = [ "--network=zulip-agora-br" ];
        };

        "zulip-rabbitmq" = {
          image = "rabbitmq:3.7.7";
          environmentFiles = [ "/run/keys/zulip-rabbitmq-env" ];
          volumes = [ "/opt/docker/zulip/rabbitmq:/var/lib/rabbitmq:rw" ];
          extraOptions = [ "--network=zulip-agora-br" ];
        };

        "zulip-redis" = {
          image = "redis:alpine";
          environmentFiles = [ "/run/keys/zulip-redis-env" ];
          volumes = [ "/opt/docker/zulip/redis:/data:rw" ];
          cmd = [
            "sh"
            "-euc"
            ''
              echo "requirepass '$REDIS_PASSWORD'" > /etc/redis.conf
              exec redis-server /etc/redis.conf
            ''
          ];
          extraOptions = [ "--network=zulip-agora-br" ];
        };

        # "zulip" = {
        #   image = "zulip/docker-zulip:4.7-0";
        #   dependsOn = [ "zulip-database" "zulip-memcached" "zulip-rabbitmq" "zulip-redis" ];
        #   ports = [ "80:80" "443:443" ];
        #   environmentFiles = [ "/run/keys/zulip-zulip-env" ];
        #   volumes = [ "/opt/docker/zulip/zulip:/data:rw" ];
        #   extraOptions = [ "--network=zulip-agora-br" "--ulimit" "nofile=1000000:1048576" ];
        # };
      };
      systemd.services."docker-zulip-redis" = let requirements = [ "zulip-redis-env-key.service" ]; in {
        after = requirements;
        requires = requirements;
      };
      systemd.services."docker-zulip-rabbitmq" = let requirements = [ "zulip-rabbitmq-env-key.service" ]; in {
        after = requirements;
        requires = requirements;
      };
      systemd.services."docker-zulip-memcached" = let requirements = [ "zulip-memcached-env-key.service" ]; in {
        after = requirements;
        requires = requirements;
      };
      systemd.services."docker-zulip-database" = let requirements = [ "zulip-postgres-env-key.service" ]; in {
        after = requirements;
        requires = requirements;
      };
      systemd.services."docker-zulip" = let requirements = [ "zulip-zulip-env-key.service" ]; in {
        after = requirements;
        requires = requirements;
      };
   };
 }
