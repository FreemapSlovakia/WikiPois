#!/bin/bash
# Applies OSM replication diffs, refreshes wiki_mv and mails the result.
#
#   update.sh            run an update (wikipois-update.service)
#   update.sh --abrupt   OnFailure= backstop for a run killed before it could report
#
# Mail settings come from update.conf (see update.conf.example).

set -uo pipefail

cd "$(dirname "$0")"

. ./update.conf

export PGPASSWORD=wiki

host="$(hostname)"

notify() { # <subject>, body on stdin
  local to_args=() emails email
  IFS=',' read -ra emails <<< "$NOTIFY_EMAIL"
  for email in "${emails[@]}"; do
    to_args+=(-F "to=${email// /}")
  done

  curl -sS --fail-with-body --retry 3 --retry-connrefused --max-time 60 \
    --user "api:$MAILGUN_API_KEY" \
    "https://api.mailgun.net/v3/$MAILGUN_DOMAIN/messages" \
    -F from="wikipois-noreply@$MAILGUN_DOMAIN" \
    "${to_args[@]}" \
    -F subject="$1" \
    -F text="$(cat)"
}

if [ "${1:-}" = --abrupt ]; then
  # A run that exited with a status has already mailed its own result.
  if [ "${MONITOR_SERVICE_RESULT:-}" = exit-code ]; then
    exit 0
  fi

  notify "WikiPois update DIED on $host" <<EOF
${MONITOR_UNIT:-wikipois-update.service} terminated without reporting a result at $(date).

  result: ${MONITOR_SERVICE_RESULT:-unknown}
  code:   ${MONITOR_EXIT_CODE:-unknown}
  status: ${MONITOR_EXIT_STATUS:-unknown}

journalctl -u ${MONITOR_UNIT:-wikipois-update.service}
EOF
  exit
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

start=$(date +%s)

{
  osm2pgsql-replication update -d wiki -U wiki -H localhost -- -a -s --flat-nodes /fm/data4/martin/wikipois-flat-nodes --cache 0 -O flex -S wiki.lua \
    && psql -U wiki -h localhost wiki -v ON_ERROR_STOP=1 -c "REFRESH MATERIALIZED VIEW CONCURRENTLY wiki_mv;"
} 2>&1 | tee "$log"
rc=$?

took="$(( ($(date +%s) - start) / 60 )) min"
status="$(osm2pgsql-replication status -d wiki -U wiki -H localhost 2>&1 | tail -n 2)"

if [ $rc -eq 0 ]; then
  notify "WikiPois update OK on $host" <<EOF
Update finished in $took.

$status
EOF
else
  notify "WikiPois update FAILED on $host" <<EOF
Update failed with exit code $rc after $took.

$status

Last lines of the log (full log: journalctl -u wikipois-update.service):

$(tail -n 50 "$log")
EOF
fi

exit $rc
