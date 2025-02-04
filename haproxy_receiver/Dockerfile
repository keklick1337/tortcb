FROM alpine:latest

RUN apk add --no-cache haproxy tor socat bash

RUN adduser -D -h /home/haproxyuser haproxyuser

COPY haproxy.cfg.template /etc/haproxy/haproxy.cfg.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
