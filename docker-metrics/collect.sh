#!/bin/sh
set -e
set -u

out="${OUTPUT_FILE:-/out/docker.prom}"
interval="${SCRAPE_INTERVAL_SECONDS:-30}"

while true; do
  tmp="${out}.tmp"

  now="$(date +%s)"

  running="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
  exited="$(docker ps -a -q --filter status=exited 2>/dev/null | wc -l | tr -d ' ')"
  paused="$(docker ps -a -q --filter status=paused 2>/dev/null | wc -l | tr -d ' ')"
  restarting="$(docker ps -a -q --filter status=restarting 2>/dev/null | wc -l | tr -d ' ')"
  created="$(docker ps -a -q --filter status=created 2>/dev/null | wc -l | tr -d ' ')"
  dead="$(docker ps -a -q --filter status=dead 2>/dev/null | wc -l | tr -d ' ')"

  total="$(
    docker ps -a -q 2>/dev/null | wc -l | tr -d ' '
  )"

  {
    echo "# HELP docker_metrics_last_scrape_timestamp_seconds Last successful scrape timestamp."
    echo "# TYPE docker_metrics_last_scrape_timestamp_seconds gauge"
    echo "docker_metrics_last_scrape_timestamp_seconds $now"

    echo "# HELP docker_containers_total Total containers (all states)."
    echo "# TYPE docker_containers_total gauge"
    echo "docker_containers_total $total"

    echo "# HELP docker_containers_running Containers currently running."
    echo "# TYPE docker_containers_running gauge"
    echo "docker_containers_running $running"

    echo "# HELP docker_containers_exited Containers in exited state."
    echo "# TYPE docker_containers_exited gauge"
    echo "docker_containers_exited $exited"

    echo "# HELP docker_containers_paused Containers in paused state."
    echo "# TYPE docker_containers_paused gauge"
    echo "docker_containers_paused $paused"

    echo "# HELP docker_containers_restarting Containers in restarting state."
    echo "# TYPE docker_containers_restarting gauge"
    echo "docker_containers_restarting $restarting"

    echo "# HELP docker_containers_created Containers in created state."
    echo "# TYPE docker_containers_created gauge"
    echo "docker_containers_created $created"

    echo "# HELP docker_containers_dead Containers in dead state."
    echo "# TYPE docker_containers_dead gauge"
    echo "docker_containers_dead $dead"

    echo "# HELP docker_container_size_rw_bytes Writable layer size in bytes per container."
    echo "# TYPE docker_container_size_rw_bytes gauge"
    echo "# HELP docker_container_size_rootfs_bytes Total container rootfs size in bytes per container."
    echo "# TYPE docker_container_size_rootfs_bytes gauge"
    echo "# HELP docker_container_up Container is running (1) else 0."
    echo "# TYPE docker_container_up gauge"

    echo "# HELP docker_volume_size_bytes Docker volume size in bytes (du of _data)."
    echo "# TYPE docker_volume_size_bytes gauge"

    echo "# HELP docker_network_info Docker network metadata (value is always 1)."
    echo "# TYPE docker_network_info gauge"
    echo "# HELP docker_network_containers Number of containers attached to a network."
    echo "# TYPE docker_network_containers gauge"
    echo "# HELP docker_network_external Network considered external (1) or not (0)."
    echo "# TYPE docker_network_external gauge"
    echo "# HELP docker_network_internal Network internal flag (1) or not (0)."
    echo "# TYPE docker_network_internal gauge"
  } >"$tmp"

  # Per-container sizes/state
  # Use `docker inspect -s` fields for byte-accurate sizes.
  ids="$(docker ps -a -q 2>/dev/null || true)"
  for id in $ids; do
    name="$(docker inspect --format '{{.Name}}' "$id" 2>/dev/null | sed 's#^/##' || true)"
    status="$(docker inspect --format '{{.State.Status}}' "$id" 2>/dev/null || true)"
    size_rw="$(docker inspect -s --format '{{.SizeRw}}' "$id" 2>/dev/null || echo 0)"
    size_rootfs="$(docker inspect -s --format '{{.SizeRootFs}}' "$id" 2>/dev/null || echo 0)"

    up="0"
    if [ "$status" = "running" ]; then
      up="1"
    fi

    # sanitize empty
    [ -n "$name" ] || name="$id"
    [ -n "$status" ] || status="unknown"
    [ -n "$size_rw" ] || size_rw="0"
    [ -n "$size_rootfs" ] || size_rootfs="0"

    printf 'docker_container_up{name="%s",id="%s",state="%s"} %s\n' "$name" "$id" "$status" "$up" >>"$tmp"
    printf 'docker_container_size_rw_bytes{name="%s",id="%s",state="%s"} %s\n' "$name" "$id" "$status" "$size_rw" >>"$tmp"
    printf 'docker_container_size_rootfs_bytes{name="%s",id="%s",state="%s"} %s\n' "$name" "$id" "$status" "$size_rootfs" >>"$tmp"
  done

  # Per-volume sizes (best-effort: requires access to /var/lib/docker/volumes on the host)
  vols="$(docker volume ls -q 2>/dev/null || true)"
  for v in $vols; do
    # Most Linux installs store volume contents in /var/lib/docker/volumes/<name>/_data
    dir="/var/lib/docker/volumes/$v/_data"
    size_kib="0"
    if [ -d "$dir" ]; then
      # busybox du doesn't always support -b; use KiB and convert
      size_kib="$(du -sk "$dir" 2>/dev/null | awk '{print $1}' | tr -d ' ' || echo 0)"
      [ -n "$size_kib" ] || size_kib="0"
    fi
    size_bytes="$((size_kib * 1024))"
    printf 'docker_volume_size_bytes{name="%s"} %s\n' "$v" "$size_bytes" >>"$tmp"
  done

  # Docker networks (mark "external" as not compose-managed and not default)
  # Heuristic: external=true if it is not one of {bridge,host,none} and does not have label com.docker.compose.project
  nets="$(docker network ls -q 2>/dev/null || true)"
  for nid in $nets; do
    nname="$(docker network inspect --format '{{.Name}}' "$nid" 2>/dev/null || true)"
    ndriver="$(docker network inspect --format '{{.Driver}}' "$nid" 2>/dev/null || true)"
    nscope="$(docker network inspect --format '{{.Scope}}' "$nid" 2>/dev/null || true)"
    ninternal="$(docker network inspect --format '{{.Internal}}' "$nid" 2>/dev/null || echo false)"
    compose_project="$(docker network inspect --format '{{ index .Labels "com.docker.compose.project" }}' "$nid" 2>/dev/null || true)"
    containers_count="$(docker network inspect --format '{{len .Containers}}' "$nid" 2>/dev/null || echo 0)"

    [ -n "$nname" ] || nname="$nid"
    [ -n "$ndriver" ] || ndriver="unknown"
    [ -n "$nscope" ] || nscope="unknown"
    [ -n "$containers_count" ] || containers_count="0"

    external="0"
    if [ "$nname" != "bridge" ] && [ "$nname" != "host" ] && [ "$nname" != "none" ]; then
      if [ -z "$compose_project" ] || [ "$compose_project" = "<no value>" ]; then
        external="1"
      fi
    fi

    # normalize boolean internal to 0/1
    internal_num="0"
    if [ "$ninternal" = "true" ]; then
      internal_num="1"
    fi

    printf 'docker_network_info{name="%s",id="%s",driver="%s",scope="%s"} 1\n' "$nname" "$nid" "$ndriver" "$nscope" >>"$tmp"
    printf 'docker_network_containers{name="%s",id="%s",driver="%s",scope="%s"} %s\n' "$nname" "$nid" "$ndriver" "$nscope" "$containers_count" >>"$tmp"
    printf 'docker_network_external{name="%s",id="%s",driver="%s",scope="%s"} %s\n' "$nname" "$nid" "$ndriver" "$nscope" "$external" >>"$tmp"
    # keep internal as part of info-like signals (reuse docker_network_external metric family to avoid more series)
    printf 'docker_network_internal{name="%s",id="%s",driver="%s",scope="%s"} %s\n' "$nname" "$nid" "$ndriver" "$nscope" "$internal_num" >>"$tmp"
  done

  mv -f "$tmp" "$out"
  sleep "$interval"
done

