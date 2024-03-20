FROM node:18.19.0 AS FRONT
WORKDIR /web
COPY ./web .
RUN yarn install --frozen-lockfile --network-timeout 1000000 && yarn run build


FROM golang:1.20.12 AS BACK
WORKDIR /go/src/casdoor
COPY . .
RUN ./build.sh
RUN go test -v -run TestGetVersionInfo ./util/system_test.go ./util/system.go > version_info.txt

FROM alpine:latest AS STANDARD
LABEL MAINTAINER="https://casdoor.org/"
ARG USER=casdoor

RUN sed -i 's/https/http/' /etc/apk/repositories
RUN apk add --update sudo
RUN apk add curl
RUN apk add ca-certificates && update-ca-certificates

RUN adduser -D $USER -u 1000 \
    && echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER \
    && chmod 0440 /etc/sudoers.d/$USER \
    && mkdir logs \
    && chown -R $USER:$USER logs

USER 1000
WORKDIR /
COPY --from=BACK --chown=$USER:$USER /go/src/casdoor/server ./server
COPY --from=BACK --chown=$USER:$USER /go/src/casdoor/swagger ./swagger
COPY --from=BACK --chown=$USER:$USER /go/src/casdoor/conf/app.conf ./conf/app.conf
COPY --from=BACK --chown=$USER:$USER /go/src/casdoor/version_info.txt ./go/src/casdoor/version_info.txt
COPY --from=FRONT --chown=$USER:$USER /web/build ./web/build

ENTRYPOINT ["/server"]


FROM debian:latest AS db
RUN apt update \
    && apt install -y \
        mariadb-server \
        mariadb-client \
    && rm -rf /var/lib/apt/lists/*


FROM db AS ALLINONE
LABEL MAINTAINER="https://casdoor.org/"

RUN apt update
RUN apt install -y ca-certificates && update-ca-certificates

WORKDIR /
COPY --from=BACK /go/src/casdoor/server ./server
COPY --from=BACK /go/src/casdoor/swagger ./swagger
COPY --from=BACK /go/src/casdoor/docker-entrypoint.sh /docker-entrypoint.sh
COPY --from=BACK /go/src/casdoor/conf/app.conf ./conf/app.conf
COPY --from=BACK /go/src/casdoor/version_info.txt ./go/src/casdoor/version_info.txt
COPY --from=FRONT /web/build ./web/build
RUN sed -i 's/\/static/https:\/\/tdn.sout.cc\/auth-static/g' /web/build/index.html
ENTRYPOINT ["/bin/bash"]
CMD ["/docker-entrypoint.sh"]
