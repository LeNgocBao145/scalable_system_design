#!/bin/bash
set -e

# This script runs during database initialization

# Create replication user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER $REPLICATION_USER WITH REPLICATION ENCRYPTED PASSWORD '$REPLICATION_PASSWORD';
EOSQL

# Create application user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
EOSQL

# Configure PostgreSQL for replication
cat >> ${PGDATA}/postgresql.conf <<EOF
listen_addresses = '*'
wal_level = replica
max_wal_senders = 3
wal_keep_size = 64
max_replication_slots = 3
EOF

# Configure pg_hba.conf for replication access
echo "host replication ${REPLICATION_USER} 0.0.0.0/0 md5" >> ${PGDATA}/pg_hba.conf
echo "host all ${DB_USER} 0.0.0.0/0 md5" >> ${PGDATA}/pg_hba.conf
