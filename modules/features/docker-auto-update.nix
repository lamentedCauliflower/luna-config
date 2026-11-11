{ ... }:
{
  flake.nixosModules.dockerAutoUpdate =
    { pkgs, ... }:
    {
      # Nightly: pull every running compose container's image tag and restart
      # the systemd unit of any stack that got a newer image. Its `up` then
      # recreates the changed containers.
      #
      # Restarting the unit rather than running `docker compose up -d` here is
      # deliberate: units carry their own compose environment (hermes'
      # HERMES_UID/GID, romm's --env-file), which a bare `up -d` would drop.
      # The unit is found from the container's compose-file label -> the
      # `docker compose -f <file> up` process -> its cgroup, so new stacks are
      # covered without registering anywhere. Pinned tags (gitea:1.25.4,
      # postgres:14) only move within that tag.
      #
      # 03:30: before autoUpgrade (04:00) and the minecraft restart (04:30).
      systemd.services.docker-auto-update = {
        description = "Pull newer images for compose stacks and restart them";
        after = [
          "docker.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        startAt = "*-*-* 03:30:00";
        path = with pkgs; [
          docker
          procps
          coreutils
          systemd
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          units=""
          for c in $(docker ps -q); do
            file=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$c")
            [ -n "$file" ] || continue
            ref=$(docker inspect -f '{{.Config.Image}}' "$c")
            if ! docker pull -q "$ref" >/dev/null; then
              echo "pull failed: $ref" >&2
              continue
            fi
            [ "$(docker image inspect -f '{{.Id}}' "$ref")" != "$(docker inspect -f '{{.Image}}' "$c")" ] || continue
            if ! pid=$(pgrep -o -f -- "-f $file up"); then
              echo "no unit runs $file, skipping $ref" >&2
              continue
            fi
            units="$units $(basename "$(cut -d: -f3 "/proc/$pid/cgroup")")"
          done

          for u in $(printf '%s\n' $units | sort -u); do
            echo "restarting $u for new images"
            systemctl try-restart "$u" || echo "restart failed: $u" >&2
          done

          docker image prune -f
        '';
      };
    };
}
