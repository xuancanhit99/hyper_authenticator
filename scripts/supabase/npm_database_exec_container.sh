#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
  exit 64
fi

database_password=${MYSQL_PASSWORD:-${MARIADB_PASSWORD:-}}
if [ -z "$database_password" ]; then
  password_file=${MYSQL_PASSWORD_FILE:-${MARIADB_PASSWORD_FILE:-}}
  case "$password_file" in
    /*) ;;
    *) exit 78 ;;
  esac
  if [ ! -f "$password_file" ] || [ -L "$password_file" ] ||
    [ ! -r "$password_file" ]; then
    exit 78
  fi
  database_password=$(cat -- "$password_file")
fi

if [ -z "$database_password" ]; then
  exit 78
fi

MYSQL_PWD=$database_password
export MYSQL_PWD
unset database_password password_file
exec "$@"
