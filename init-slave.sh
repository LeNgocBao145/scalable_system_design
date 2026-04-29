#!/bin/bash
set -e

# Wait for master to be ready
echo "Waiting for master database..."
until PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres-master -U $POSTGRES_USER -c '\q' 2>/dev/null; do
    sleep 2
done
echo "Master is ready"

# Check if this is first run (data directory is empty)
if [ ! -s "${PGDATA}/PG_VERSION" ]; then
    echo "First run detected. Setting up replication from master..."
    
    # Remove any existing data
    rm -rf ${PGDATA}/*
    
    # Perform base backup from master
    PGPASSWORD=$REPLICATION_PASSWORD pg_basebackup \
        -h postgres-master \
        -D ${PGDATA} \
        -U $REPLICATION_USER \
        -P \
        -R \
        -X stream \
        -c fast
    
    # Configure slave-specific settings
    cat >> ${PGDATA}/postgresql.conf <<EOF
listen_addresses = '*'
hot_standby = on
EOF
    
    # Fix ownership and permissions
    chown -R postgres:postgres ${PGDATA}
    chmod 700 ${PGDATA}
    
    echo "Replication setup complete"
else
    echo "Data directory exists. Skipping replication setup."
fi

# Start PostgreSQL as postgres user
exec su-exec postgres postgres
