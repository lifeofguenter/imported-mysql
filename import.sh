#!/usr/bin/env bash

throw_exception() {
  # cleanup launched ec2 instances
  if [[ ! -z "${cleanup_ec2}" ]] && [[ ! -z "${ec2_id}" ]]; then
    consolelog "Deleting ec2: ${ec2_id}" "error"
    aws::del_ec2 "${ec2_id}"
    ec2_id=
  fi

  consolelog "Ooops!" "error"
  echo 'Stack trace:' 1>&2
  while caller $((n++)) 1>&2; do :; done;
  exit 1
}

consolelog() {
  local color
  local ts

  # el-cheapo way to detect if timestamp prefix needed
  if [[ ! -z "${JENKINS_HOME}" ]]; then
    ts=''
  else
    ts="[$(date -u +'%Y-%m-%d %H:%M:%S')] "
  fi

  color_reset='\e[0m'

  case "${2}" in
    success )
      color='\e[0;32m'
      ;;
    error )
      color='\e[1;31m'
      ;;
    * )
      color='\e[0;37m'
      ;;
  esac

  if [[ ! -z "${1}" ]] && [[ ! -z "${2}" ]] && [[ "${2}" = "error" ]]; then
    printf "${color}%s%s: %s${color_reset}\n" "${ts}" "${0##*/}" "${1}" >&2
  elif [[ ! -z "${1}" ]]; then
    printf "${color}%s%s: %s${color_reset}\n" "${ts}" "${0##*/}" "${1}"
  fi

  return 0
}

waitfor::tcpup() {
  while ! echo 'foo' | ncat -w 2 "${1}" "${2}" &> /dev/null; do
    echo -n '.'
    sleep 5
  done
  sleep 10
  echo ''
}

set -E
trap 'throw_exception' ERR

# add client cnf
cat <<EOF > ~/.my.cnf
[client]
host = 127.0.0.1
user = root
password = ${MYSQL_ROOT_PASSWORD}
EOF

# remove problematic server config options
find /etc/mysql/ -name '*.cnf' -print0 \
  | xargs -0 grep -lZE '^(datadir)' \
  | xargs -rt -0 sed -Ei 's/^(datadir)/#&/'

# set datadir away from VOLUME
cat <<EOF > /etc/mysql/conf.d/datadir.cnf
[mysqld]
datadir = /var/lib/mysql2
EOF

/entrypoint.sh mysqld &

sleep 10
consolelog "waiting for mysqld..."
waitfor::tcpup "127.0.0.1" "3306"
sleep 10

for sqlfile in /dumps/*_structure.sql; do
  base_name="${sqlfile##*/}"
  db="${base_name/_structure.sql/}"
  mysql -e "CREATE DATABASE IF NOT EXISTS \`${db}\`;"

  consolelog "importing /dumps/${db}_structure.sql ..."
  cat "/dumps/${db}_structure.sql" | mysql "${db}"
  consolelog "importing /dumps/${db}_data* ..."
  cat "/dumps/${db}_data"*.sql | mysql "${db}"
done

if [[ -f "/dumps/custom.sql" ]]; then
  consolelog "importing /dumps/custom.sql ..."
  mysql < "/dumps/custom.sql"
fi

killall mysqld
