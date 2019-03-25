FROM mysql:5.7

ARG MYSQL_ROOT_PASSWORD

RUN mkdir -p /dumps/

COPY import.sh /usr/local/bin/import.sh

# add below to your own Dockerfile
#COPY *.sql /dumps/
#RUN /dumps/import.sh
