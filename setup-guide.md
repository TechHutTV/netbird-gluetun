# Run a NetBird exit node through Gluetun and AirVPN

This article shows NetBird users how to run an exit node in Docker and send the exit node's internet traffic through an AirVPN WireGuard tunnel. It covers the NetBird objects, host configuration, routing, DNS, validation, and routine operations needed for a complete deployment.

When a device selects this exit node, its internet traffic follows this path:

```text
Your device → NetBird exit node → Gluetun → AirVPN → Internet
```

This configuration uses AirVPN WireGuard and IPv4. It blocks forwarded traffic when the provider tunnel is unavailable. The design was tested for IP routing, DNS handling, provider outages, and container recovery. Run the checks in this guide on your own network before treating the exit as a required isolation boundary.

## Before you start

Have these ready:

- A Linux host with Docker Engine and the Docker Compose plugin.
- Permission to run Docker commands on that host.
- Administrator access to your existing NetBird account.
- An AirVPN account, WireGuard credentials, and a reserved forwarded port.
- A NetBird device to use for validation.

The host needs `/dev/net/tun`. Check the Docker installation and tunnel device:

```sh
docker version
docker compose version
ls -l /dev/net/tun
```

You do not need to connect the host's own NetBird client. The exit node runs inside Docker.

## 1. Prepare the deployment directory

Put the deployment files in a directory of your choice, then open a terminal there. Keep this structure:

```text
netbird-gluetun/
├── compose.yaml
├── .env.example
├── vpn-init.sh
├── post-rules.txt
└── gluetun/
    └── servers.json
```

These files are required for the main deployment. Keep `client-compose.yaml` only if you want the optional validation container described at the end.

For a new installation, create your environment file:

```sh
cp -n .env.example .env
chmod 600 .env
```

If you already have a `.env` in this folder, edit that file instead of replacing it. Never publish `.env`; it contains the AirVPN private key and the NetBird setup key.

## 2. Enter your NetBird and AirVPN settings

Open `.env` in your preferred text editor. Fill in these settings:

| Setting | Value |
| --- | --- |
| `NETBIRD_MANAGMENT_URL` | Your existing NetBird management server's base URL, including `https://`. |
| `VPN_SERVICE_PROVIDER` | `airvpn` |
| `VPN_TYPE` | `wireguard` |
| `WIREGUARD_PRIVATE_KEY` | The private key from your AirVPN WireGuard configuration. |
| `WIREGUARD_PRESHARED_KEY` | The preshared key from the same configuration. |
| `WIREGUARD_ADDRESSES` | The IPv4 tunnel address and prefix from that configuration. |
| `SERVER_COUNTRIES` | Your chosen AirVPN server country. |
| `SERVER_CITIES` | Your chosen city within that country. |
| `FIREWALL_VPN_INPUT_PORTS` | A UDP-capable port reserved in your AirVPN account. |
| `TZ` | Your time zone, such as `Etc/UTC`. |

`MANAGMENT` is intentionally spelled that way in the example files. Keep the spelling so Compose can read the setting.

Gluetun selects the AirVPN server using the country and city settings. The Compose file passes the reserved port to both Gluetun and NetBird, so they use the same port. It does not publish a port on the Docker host.

Leave `NETBIRD_EXIT_SETUP_KEY` empty until you create the setup key in the NetBird dashboard. The optional `NETBIRD_CLIENT_SETUP_KEY` is only needed by `client-compose.yaml`; you can leave it empty for the main deployment. 

Keep `.env` private. To validate Compose later, use `docker compose config --quiet`; the command without `--quiet` prints resolved credentials.

## 3. Create the NetBird configuration

Create the NetBird objects in the dashboard before starting Docker. The deployment only needs the setup key you paste into `.env`.

Sign in to your NetBird dashboard and create the following groups:

| Group | Members | Purpose |
| --- | --- | --- |
| `gluetun-exit` | Empty initially | Receives the Docker exit node. |
| `gluetun-users` | Devices allowed to use the exit | Controls which devices can select the route. |

The names are examples. Use your own naming convention consistently in the remaining steps.

Create a one-use setup key for the Docker exit node:

1. Open **Setup Keys** and create a key with one use and a short expiration.
2. Assign it automatically to the `gluetun-exit` group.
3. Leave the key non-ephemeral so the Docker peer keeps its identity after a restart.
4. Copy the key into `.env` as `NETBIRD_EXIT_SETUP_KEY`.

Create an IPv4 route:

1. Open **Networks** or **Routes**, depending on your dashboard version, and create a route for `0.0.0.0/0`.
2. Select the `gluetun-exit` peer group as the routing peer group.
3. Select `gluetun-users` as the source group.
4. Enable masquerading.
5. Disable Auto Apply so devices opt in by selecting the route.
6. Give it a recognizable name such as `gluetun-internet`.

Create an access policy that permits the users group to reach the exit group for ICMP diagnostics. Use `gluetun-users` as the source, `gluetun-exit` as the destination, and ICMP as the protocol. This policy is optional for internet forwarding, but it makes peer troubleshooting easier.

Create a DNS configuration for `gluetun-users` with `1.1.1.1` and `1.0.0.1` as the primary nameservers. Review any existing DNS groups and internal domains before enabling it. The Docker exit disables its own NetBird DNS listener so Gluetun remains the resolver inside the shared namespace.

The route remains inactive for a device until that device belongs to `gluetun-users` and selects it. The Docker configuration also enables NetBird Block LAN access, so the exit does not provide a path to its local network.

Setup keys are single-use credentials. Start the containers soon after creating the exit key. Once the exit registers, its identity is stored in the Docker volume `netbird-exit`; keep that volume when recreating the containers.

## 4. Start the exit node

From the deployment directory, run:

```sh
docker compose config --quiet
docker compose up -d
docker compose ps
```

The deployment starts three containers:

| Container | Purpose |
| --- | --- |
| the `netns` service | Keeps the shared network environment available when Gluetun is replaced. |
| the `gluetun` service | Connects to AirVPN and runs the VPN firewall. |
| the `netbird` service | Connects to NetBird and forwards client traffic. |

Wait for the `gluetun` service to become healthy. Then check NetBird:

```sh
docker compose exec netbird netbird status -d
```

Management and Signal should be connected. The exit should have a NetBird address and use your reserved WireGuard port. In your NetBird dashboard, confirm that the new peer is in the exit group you created and that the default route is available to the users group.

Get the current AirVPN public address:

```sh
docker compose exec gluetun wget -qO- http://127.0.0.1:8000/v1/publicip/ip
```

Save that address for the next step. It can change when Gluetun reconnects.

## 5. Use the exit from an existing NetBird device

Start with one device you control. In your NetBird dashboard, add it to the users group you created. You do not need to reinstall NetBird or register that device again.

If you reach the selected device over SSH, make sure you have console access or another recovery method before changing its default route. Selecting an exit can change the return path for your SSH connection.

On the selected device, check its normal public address, then select the exit:

```sh
curl -4 https://ifconfig.me/ip
netbird networks list
netbird networks select gluetun-internet
```

Some systems require `sudo` for the NetBird commands. Allow a few seconds for the route to become active, then run:

```sh
curl -4 https://ifconfig.me/ip
netbird status -d
```

The public address should now match Gluetun's current AirVPN address. In the detailed status, find the exit peer. `Connection type: P2P` indicates a direct connection; a relayed connection may have different performance.

To return to the device's normal internet connection:

```sh
netbird networks deselect gluetun-internet
```

Repeat the public-address check to confirm the change.

## 6. Check DNS and outage behavior

A matching public IP confirms basic routing. It does not, by itself, prove that DNS and other traffic cannot escape outside the VPN.

With the exit selected, check DNS on the selected device:

```sh
dig +short myip.opendns.com @resolver1.opendns.com
dig whoami.akamai.net
```

The first command should report the AirVPN address. The second gives information about the resolver handling the query. Cached answers can be misleading; neither command alone is a complete DNS leak test.

This deployment is IPv4-only. On every device that needs strict isolation, check IPv6 as well:

```sh
curl -6 --max-time 10 https://ifconfig.me/ip
```

If it returns a public IPv6 address while this exit is selected, the device has an alternate internet path that must be addressed before use.

Before depending on the exit for isolation in another environment, repeat the outage checks there. During testing, this configuration blackholed clients during provider loss and recovered after container replacement. Use the outage procedure described in the next paragraph to verify the behavior on your own network.

Deselecting the exit or stopping NetBird on a client is outside the exit container's control. Devices that must never use their ordinary internet connection need their own enforced restrictions too.

## Everyday commands

View container status and recent VPN logs:

```sh
docker compose ps
docker compose logs --tail 60 gluetun
```

Restart the NetBird container:

```sh
docker compose restart netbird
```

Recreate Gluetun after changing its environment settings:

```sh
docker compose up -d --force-recreate gluetun
```

The tested stack restored all three client paths automatically after this operation. Check client connectivity afterward because provider and network conditions differ between deployments.

Stop the deployment while keeping its saved NetBird identity:

```sh
docker compose down
```

Start it again:

```sh
docker compose up -d
```

Avoid `docker compose down -v` unless you intend to delete the saved identity. A used setup key cannot register a replacement identity.

## Troubleshooting

**Gluetun never becomes healthy.** Check the AirVPN keys, tunnel address, country, and city in `.env`, then inspect the Gluetun logs. Review logs before sharing them so you do not disclose credentials.

**NetBird fails to register.** Check the management URL and setup key. If the one-use exit key expired before registration, create a replacement assigned to the exit group and update `NETBIRD_EXIT_SETUP_KEY` in `.env`. Recreate the NetBird container after changing it.

**The route is missing on your device.** Confirm the device belongs to the users group, the route is enabled, and the exit peer is connected. Allow time for the device to receive its updated configuration.

**The route is selected, but internet access fails.** Confirm Gluetun is healthy and both `vpn-init.sh` and `post-rules.txt` are present. The post-rules file is intentionally comments only. Check the routing rules:

```sh
docker compose exec gluetun ip rule
```

The priority-99 rule in `vpn-init.sh` is needed to send replies back to NetBird peers. The same script enforces VPN-only forwarding and removes stale Gluetun rules during replacement. Keep the included initialization and firewall files with the Compose file.

**A changed NetBird setting does not take effect.** NetBird persists settings in its volume. Some changes require an explicit disconnect and reconnect inside the container. Do not delete the volume as your first troubleshooting step.

**Speeds are lower than expected.** Check whether the peer connection is direct or relayed. This setup nests one encrypted tunnel inside another; route quality, packet loss, and MTU affect performance. The example Gluetun MTU is `1400`. Measure from your own client because results depend on the selected AirVPN server and network path.

## Optional test container and cleanup

If you want to validate the deployment without changing an existing device, create a second one-use setup key in the NetBird dashboard, assign it to the users group, and put it in `NETBIRD_CLIENT_SETUP_KEY`. Then the included `client-compose.yaml` starts a separate NetBird client:

```sh
docker compose -f client-compose.yaml up -d
docker compose -f client-compose.yaml exec netbird-client netbird networks select gluetun-internet
docker compose -f client-compose.yaml exec netbird-client netbird status -d
docker compose -f client-compose.yaml exec netbird-client wget -qO- --timeout=10 https://ifconfig.me/ip
```

The last command should print Gluetun's current AirVPN address. The validation container uses its dedicated setup key and its own persistent volume. Starting it does not select the exit on the Docker host.

For complete removal, first remove the exit route, policy, DNS configuration, groups, and setup key from the NetBird dashboard. Then stop the containers with `docker compose down`. Add `-v` only if you also want to delete the saved Docker identities; deleting the `netbird-exit` volume means the peer must register again with a new setup key.
