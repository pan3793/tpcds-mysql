FROM mysql:8.0.21

ENV MYSQL_ALLOW_EMPTY_PASSWORD=yes \
    MYSQL_DATABASE=tpcds
COPY query_log.cnf /etc/mysql/conf.d
COPY tpcds-kit /tmp/tpcds-kit
COPY entrypoint.sh /entrypoint.sh
COPY script.sh /docker-entrypoint-initdb.d