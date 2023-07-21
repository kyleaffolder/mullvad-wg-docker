#!/bin/bash

set -e

# For testing:
# SERVER_LOCATION=''
# SERVER_LOCATION='us-chi'
# SERVER_LOCATION='us-chi,us-slc'

default_route_ip=$(ip route | grep default | awk '{print $3}')
if [[ -z "$default_route_ip" ]]; then
  echo "No default route configured" >&2
  exit 1
fi

# If Mullvad VPN location is not-specified, set to Sweden - by default
if [[ -z "$SERVER_LOCATION" ]]; then
  SERVER_LOCATION=se
fi

export ACCOUNT
if [[ -z "$PRIVATE_KEY" ]]; then
  export PRIVATE_KEY
fi
# [[ -z "$PRIVATE_KEY" ]] && export PRIVATE_KEY

configs=$(find /etc/wireguard/conf/mullvad -type f -printf "%f\n")
if [[ -z "$configs" ]]; then
  echo -e "No configuration files found in /etc/wireguard/conf/mullvad\nGenerating Mullvad WireGuard configuration files...\n" >&2
  # bash /VPN/mullvad-wg.sh
  source /VPN/mullvad-wg.sh
fi

unset ACCOUNT
if [[ -z "$PRIVATE_KEY" ]]; then
  unset PRIVATE_KEY
fi
# [[ -z "$PRIVATE_KEY" ]] && unset PRIVATE_KEY

# If `SERVER_LOCATION` is a comma-separated list, push each individual item to a new `patterns` array,
if [[ "$SERVER_LOCATION" =~ .*",".* ]]; then
  IFS=',' read -ra patterns <<<"$SERVER_LOCATION"
# ..otherwise, pass `SERVER_LOCATION` directly to `patterns` array
else
  patterns+=($SERVER_LOCATION)
fi
# printf '%s\n' "${patterns[@]}"

shopt -s nullglob
for i in "${patterns[@]}"; do
  files+=(/etc/wireguard/conf/mullvad/$i*.conf)
done
shopt -u nullglob
# printf '%s\n' "${files[@]}"

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No matching configuration files!"
  exit
fi

# Randomly select a WireGuard config file from available Mullvad configs (will take into account if specific locations are passed via `SERVER_LOCATION` env variable)
RANDOM_CONFIG=${files[$RANDOM % ${#files[@]}]}
echo -e "Selected WireGuard configuration: $RANDOM_CONFIG\n"
RANDOM_SERVER="$(echo "$RANDOM_CONFIG" | sed -e 's/\/etc\/wireguard\/conf\/mullvad\///g' -e 's/.conf//g')"
echo "WireGuard configuration updated to use the following Mullvad VPN exit location:"
echo -e "  ${SERVER_LOCATIONS["$RANDOM_SERVER"]} ($RANDOM_SERVER)\n"
VPN=$RANDOM_SERVER

unset SERVER_LOCATIONS

if [[ "$(cat /proc/sys/net/ipv4/conf/all/src_valid_mark)" != "1" ]]; then
  echo "sysctl net.ipv4.conf.all.src_valid_mark=1 is not set" >&2
  exit 1
fi

# The net.ipv4.conf.all.src_valid_mark sysctl is set when running the Docker container, so don't have WireGuard also set it
sed -i "s:sysctl -q net.ipv4.conf.all.src_valid_mark=1:echo Skipping setting net.ipv4.conf.all.src_valid_mark:" /usr/bin/wg-quick
# Bring up a WireGuard interface
wg-quick up $VPN

# IPv4 kill switch: traffic must be either (1) to the WireGuard interface, (2) marked as a WireGuard packet, (3) to a local address, or (4) to the Docker network
docker_network="$(ip -o addr show dev eth0 | awk '$3 == "inet" {print $4}')"
docker_network_rule="$([ ! -z "$docker_network" ] && echo "! -d $docker_network" || echo "")"
iptables -I OUTPUT ! -o $VPN -m mark ! --mark $(wg show $VPN fwmark) -m addrtype ! --dst-type LOCAL $docker_network_rule -j REJECT

# IPv6 kill switch: traffic must be either (1) to the WireGuard interface, (2) marked as a WireGuard packet, (3) to a local address, or (4) to the Docker network
docker6_network="$(ip -o addr show dev eth0 | awk '$3 == "inet6" {print $4}')"
if [[ "$docker6_network" ]]; then
  docker6_network_rule=$([ ! -z "$docker6_network" ] && echo "! -d $docker6_network" || echo "")
  ip6tables -I OUTPUT ! -o $VPN -m mark ! --mark $(wg show $VPN fwmark) -m addrtype ! --dst-type LOCAL $docker6_network_rule -j REJECT
else
  echo "Skipping IPv6 kill switch setup since IPv6 interface was not found" >&2
fi

# Support LOCAL_NETWORK environment variable, which was replaced by LOCAL_SUBNETS
if [[ -z "$LOCAL_SUBNETS" && "$LOCAL_NETWORK" ]]; then
  LOCAL_SUBNETS=$LOCAL_NETWORK
fi

# Support LOCAL_SUBNET environment variable, which was replaced by LOCAL_SUBNETS (plural)
if [[ -z "$LOCAL_SUBNETS" && "$LOCAL_SUBNET" ]]; then
  LOCAL_SUBNETS=$LOCAL_SUBNET
fi

for local_subnet in ${LOCAL_SUBNETS//,/$IFS}; do
  echo "Allowing traffic to local subnet ${local_subnet}" >&2
  ip route add $local_subnet via $default_route_ip
  iptables -I OUTPUT -d $local_subnet -j ACCEPT
done

# Output external IP address
bash /VPN/check-ip.sh

shutdown() {
  wg-quick down $interface
  exit 0
}

trap shutdown SIGTERM SIGINT SIGQUIT

sleep infinity &
wait $!
