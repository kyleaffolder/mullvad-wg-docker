FROM alpine

LABEL org.opencontainers.image.documentation=https://github.com/kyleaffolder/mullvad-wg-docker/blob/main/README.md
LABEL org.opencontainers.image.source=https://github.com/kyleaffolder/mullvad-wg-docker
LABEL org.opencontainers.image.licenses=MIT
LABEL org.opencontainers.image.title="Mullvad VPN (WireGuard)"
LABEL org.opencontainers.image.description="Docker image for connecting to Mullvad VPN via the WireGuard VPN protocol"

RUN \
  mkdir /VPN && \
  mkdir -p /etc/wireguard/conf/mullvad
COPY . /VPN

## Quick build test
RUN \
  chmod +x /VPN/check-ip.sh && \
  chmod +x /VPN/mullvad-wg.sh && \
  chmod +x /VPN/startup.sh && \
  apk --no-cache add \
    ip6tables \
    findutils \
    iptables \
    iproute2 \
    jq \
    curl \
    openresolv \
    wireguard-tools \
    iputils \
    bash \
    grep \
    net-tools \
    ts \
  && sed -i '/sysctl/d' /usr/bin/wg-quick

ENTRYPOINT bash /VPN/startup.sh
