FROM alpine:3.18.0
RUN apk update && apk add rsync bash

COPY rsync.sh /
ENTRYPOINT ["/rsync.sh"]

