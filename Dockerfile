FROM debian:bullseye AS builder

RUN apt-get update && apt-get install -y

FROM postgres:17.6

# COPY --from=builder /server /home/server

COPY ./docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY ./postgres/init.sql /docker-entrypoint-initdb.d/init.sql

RUN apt update
RUN apt install -y curl

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 5449

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["postgres"]
