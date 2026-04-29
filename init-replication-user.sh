#!/bin/bash
set -e

echo "REPLICATION_USER=$REPLICATION_USER"
echo "DB_USER=$DB_USER"

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=rep_user="$REPLICATION_USER" \
  --set=rep_pass="$REPLICATION_PASSWORD" \
  --set=db_user="$DB_USER" \
  --set=db_pass="$DB_PASSWORD" \
  --set=db_name="$DB_NAME" <<'EOSQL'

-- Replication user
DO
$$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = :'rep_user'
   ) THEN
      CREATE ROLE :"rep_user" WITH REPLICATION LOGIN PASSWORD :'rep_pass';
   END IF;
END
$$;

-- App user
DO
$$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = :'db_user'
   ) THEN
      CREATE ROLE :"db_user" WITH LOGIN PASSWORD :'db_pass';
   END IF;
END
$$;

GRANT ALL PRIVILEGES ON DATABASE :"db_name" TO :"db_user";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO :"db_user";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO :"db_user";

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON TABLES TO :"db_user";

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON SEQUENCES TO :"db_user";

EOSQL