# [kyleaffolder/mullvad-wg-docker](https://github.com/kyleaffolder/mullvad-wg-docker)

This is a simple Docker image to run a WireGuard client for the Mullvad VPN service. It is based on their configuration script which uses their API to generate configs for WireGuard.

This image also includes a built-in kill switch (based on `iptables`) to ensure that any traffic not encrypted via WireGuard is dropped.

WireGuard is implemented as a kernel module, which is key to its performance and simplicity. However, this means that WireGuard _must_ be installed on the host operating system for this container to work properly. Instructions for installing WireGuard can be found [here](http://wireguard.com/install).

## Note on `iptables`

Some hosts may not load the iptables kernel modules by default. In order for the container to be able to load them, you need to assign the `SYS_MODULE` capability and add the optional `/lib/modules` volume mount. Alternatively you can `modprobe` them from the host before starting the container.

<!-- ## Server Rotation

This container randomizes and handles Mullvad server rotation upon every restart. The Mullvad server that WireGuard is connected to will also be randomized every 6 hours. -->

## Usage

Here are some example snippets to help you get started creating a container.

### Docker Compose (recommended)

```yml
version: "3"
services:
  wireguard:
    container_name: wireguard
    image: ghcr.io/kyleaffolder/mullvad-wg-docker
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - ACCOUNT=your-16-digit-Mullvad-account-key
      - PRIVATE_KEY=optional-pregenerated-Mullvad-private-key
      - SERVER_LOCATION=se
    sysctls:
      net.ipv4.conf.all.src_valid_mark: 1
      # You may need to uncomment one or more of the following lines if you receive IPv6 related errors in the log and a connection cannot be established
      # net.ipv6.conf.all.disable_ipv6: 0
      # net.ipv6.conf.default.disable_ipv6: 0
      # net.ipv6.conf.lo.disable_ipv6: 0
    restart: unless-stopped
    # healthcheck:
    #   test: wget --no-verbose --tries=1 --spider http://localhost:32400/web || exit 1
    #   interval: 5m
    #   timeout: 10s
    #   retries: 1
    #   start_period: 20s

  curl:
    image: appropriate/curl
    command: http://httpbin.org/ip
    network_mode: service:wireguard
    depends_on:
      - wireguard
```

### Docker CLI

```bash
docker run --name wireguard \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  -e ACCOUNT=################ \
  -e PRIVATE_KEY=optional-pregenerated-Mullvad-private-key \
  -e SERVER_LOCATION=se \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  # --sysctl net.ipv6.conf.all.disable_ipv6=0  # see below `Note` \
  kyleaffolder/mullvad-wg-docker
```

Afterwards, you can link other containers to this one:

```bash
docker run -it --rm \
  --net=container:wireguard \
  appropriate/curl http://httpbin.org/ip
```

_**Note:** You may need to add in one or more of the following options if you receive IPv6 related errors in the log and a connection cannot be established:_
 - _`--sysctl net.ipv6.conf.all.disable_ipv6=0`_
 - _`--sysctl net.ipv6.conf.default.disable_ipv6=0`_
 - _`--sysctl net.ipv6.conf.lo.disable_ipv6=0`_

## Maintaining local access to attached services

When routing via WireGuard from another container using the service option in docker, you might lose access to the containers webUI locally. To avoid this and allow traffic from your local network to access that service, specify the subnet(s)[^1] using the `LOCAL_SUBNETS` environment variable:

```bash
docker run... \
  -e LOCAL_SUBNETS=10.1.0.0/16,10.2.0.0/16,10.3.0.0/16 \
  kyleaffolder/mullvad-wg-docker
```

Additionally, you may expose ports to allow your local network to access services linked to the WireGuard container:

```bash
# Expose port 80 from within the Docker container to port 8080 externally on the Docker host
docker run...
  -p 8080:80 \
  kyleaffolder/mullvad-wg-docker
```

## Parameters:

Container images are configured using parameters passed at runtime (such as those above). These parameters are separated by a colon and indicate `<external>:<internal>` respectively. For example, `-p 8080:80` would expose port `80` from inside the container to be accessible from the host's IP on port `8080` outside the container.

| Parameter | Function |
| ------------ | ------------- |
| `-e ACCOUNT=` | **Required** - Your 16-digit Mullvad account key. |
| `-e PRIVATE_KEY=` | _Optional_ - You may enter a private key that has been pregenerated from within the web admin panel of your Mullvad account. (A new private key will be generated and assigned to your Mullvad account if one is not-specified via this env variable.) |
| `-e SERVER_LOCATION=` | _Optional_ - By default, when starting this container, one server will be randomly selected (from the complete list of Mullvad servers) to connect to. You may specify one or more comma-separated country and/or server-locations (prefixed)[^1] to narrow the pool of available Mullvad servers that WireGuard will randomly connect to. |
| `-e LOCAL_SUBNETS=10.1.0.0/16` | _Optional_ - One or more local subnets that you would like to whitelist within the container (aka. will allow you to access a service running via this container from your local network).[^2] |
| `-v /lib/modules` | _Optional_ - Host kernel modules for situations where they're not already loaded. |
| `--sysctl net.ipv4.conf.all.src_valid_mark=1` | **Required** |
| _`--sysctl net.ipv6.conf.all.disable_ipv6=0`_ | _Optional - May be necessary if you receive IPv6 related errors in the log and a connection cannot be established_ |
<!-- | _`--sysctl net.ipv6.conf.default.disable_ipv6=0`_ | _Optional_ - | -->
<!-- | _`--sysctl net.ipv6.conf.lo.disable_ipv6=0`_ | _Optional_ - | -->

## Environment variables from files (Docker secrets)

You can set any environment variable from a file by using a special prepend `FILE__`.

As an example:

```bash
-e FILE__PASSWORD=/run/secrets/mullvad-account
```

Will set the environment variable `ACCOUNT` based on the contents of the `/run/secrets/mullvad-account` file.

## Support Info

- Shell access whilst the container is running: `docker exec -it wireguard /bin/bash`
- To monitor the logs of the container in realtime: `docker logs -f wireguard`
- Get container version number: `docker inspect -f '{{ index .Config.Labels "build_version" }}'`
- Get WireGuard image version number: `docker inspect -f '{{ index .Config.Labels "build_version" }}' ghcr.io/kyleaffolder/mullvad-wg-docker:latest`

## Updating Info

This image is static, versioned, and requires an image update and container recreation to update the WireGuard package inside. (I do not recommend updating the WireGuard package inside the container.)

Below are the instructions for updating this container:

### via Docker Compose

- Update the image: `docker compose pull wireguard`
- Update the container: `docker compose up -d wireguard`
- You can also remove the old dangling image: `docker image prune`

### via Docker run

- Update the image: `docker pull ghcr.io/kyleaffolder/mullvad-wg-docker`
- Stop the running container: `docker stop wireguard`
- Delete the container: `docker rm wireguard`
- Recreate a new container with teh same docker run parameters as instructed above: `docker run...`
- You can also remove the old dangling image: `docker image prune`

### via Watchtower auto-updater (only use if you don't remember the original parameters)

- Pull the latest image at its tag and replace it with the same env variables in one run:

  ```bash
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    containrrr/watchtower \
    --run-once wireguard
  ```

- You can also remove the old dangling image: `docker image prune`

**Note:** I do not recommend the use of Watchtower as a solution to automated updates of this Docker container. However, this is a useful tool for a one-time manual update of the container where you have forgotten the original parameters. In the long term, I highly recommend using Docker Compose.

### Image Update Notifications &ndash; Diun (Docker Image Update Notifier)

We recommend [Diun](https://crazymax.dev/diun/) for update notifications. Other tools that automatically update containers unattended are not recommended or supported.

## Building locally

If you want to make local modifications to this image for development purposes or just to customize the logic:

```bash
git clone https://github.com/kyleaffolder/mullvad-wg-docker.git
cd mullvad-wg-docker
docker build \
  --no-cache \
  --pull \
  -t ghcr.io/kyleaffolder/mullvad-wg-docker:latest .
```

## Versions

- **21.07.23:** - Initial release.

WireGuard's behavior may change in the future. For this reason, it's recommended to specify an image tag when running this container, such as `kyleaffolder/mullvad-wg-docker:1.0`.

The available tags are listed [here](https://github.com/kyleaffolder/mullvad-wg-docker/tags).

<!-- Footnotes -->
[^1]: Prefixed values can be found within your Mullvad VPN account. 
  - For example, specifying `us-chi` will include all US Chicago-based Mullvad server endpoints.
  - As a second example, specifying `se` will select all Mullvad servers located in Sweden.
  - As a final example, specifying `us-chi,se` will in-turn select all servers in both Chicago, USA and Sweden.
[^2]: If you would like to specify multiple subnets, please separate each IP/Range by comma.