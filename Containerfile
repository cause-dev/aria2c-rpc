FROM alpine:3.24.3

RUN apk add --no-cache aria2 ca-certificates tzdata

COPY aria2.conf /etc/aria2/aria2.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /config /downloads

VOLUME ["/config", "/downloads"]
EXPOSE 6800 6888 6888/udp

ENTRYPOINT ["/entrypoint.sh"]
