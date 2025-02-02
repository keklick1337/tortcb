# ===============================================================
# Project Name: Tor TCP Chain Balancer
# Author: Vladislav Tislenko aka keklick1337
# Date: 2 February 2025
# ===============================================================

FROM alpine:latest

RUN apk add --no-cache tor curl jq bash procps

RUN mkdir -p /etc/tor/instances && mkdir -p /var/lib/tor/hidden_services

RUN adduser -D -h /home/toruser toruser

RUN chown -R toruser:toruser /etc/tor/instances
RUN chown -R toruser:toruser /var/lib/tor/hidden_services

COPY torrc.template /etc/tor/torrc.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
