> This was only validated in a sand boxed environment, most testing to follow. Would not recommend in production. 

# NetBird exit node through Gluetun and AirVPN

Run a NetBird exit node in Docker and send its internet traffic through an AirVPN WireGuard tunnel. This repository provides the Compose stack, VPN-only firewall, and a first-time setup guide for administrators who already use NetBird.

```text
NetBird client → Docker exit node → Gluetun → AirVPN → Internet
```

The exit node shares one persistent Docker network namespace between a namespace holder, Gluetun, and NetBird. Gluetun owns the provider tunnel and resolver. NetBird advertises the exit route and carries traffic from selected peers. The firewall drops forwarded traffic when the AirVPN tunnel is unavailable, preventing an ordinary internet fallback.

## What this repository provides

- A pinned Gluetun and NetBird Compose stack.
- AirVPN WireGuard configuration with no host port publishing.
- A persistent namespace holder so container replacement does not strand the NetBird peer.
- VPN-only forwarding and return-path routing for NetBird peers.
- IPv4-only operation with IPv6 disabled explicitly.
- LAN blocking on the NetBird exit peer.
- A dashboard-based setup flow that does not require a management API token or provisioning script.
- An optional separate NetBird client for validation.

## Requirements

- A Linux host with Docker Engine and the Docker Compose plugin.
- `/dev/net/tun` available to Docker.
- An existing NetBird account with administrator access to create groups, setup keys, routes, policies, and DNS settings.
- An AirVPN account with a WireGuard configuration and a reserved forwarded UDP port.
- A NetBird device for validation.

The host's own NetBird client does not need to be connected. The exit node runs inside Docker.

## Quick start

Read [setup-guide.md](setup-guide.md) before starting. It explains the NetBird dashboard objects and the AirVPN values required by the Compose file.

Create the environment file and protect it:

```sh
cp .env.example .env
chmod 600 .env
```

Fill in the AirVPN values and paste the one-use NetBird exit setup key into `NETBIRD_EXIT_SETUP_KEY`. Then validate and start the stack:

```sh
docker compose config --quiet
docker compose up -d --wait
docker compose ps
```

Check the two services that matter after startup:

```sh
docker compose exec netbird netbird status -d
docker compose exec gluetun wget -qO- http://127.0.0.1:8000/v1/publicip/ip
```

Add a device to the NetBird users group, select the default route you created, and confirm that its public IPv4 address matches the Gluetun address.

## NetBird configuration

Create these objects in the NetBird dashboard:

| Object | Purpose |
| --- | --- |
| Exit group | Contains the Docker NetBird peer. |
| Users group | Contains devices allowed to select the exit route. |
| One-use exit setup key | Registers the Docker peer into the exit group. |
| IPv4 route `0.0.0.0/0` | Sends selected users' internet traffic through the exit peer. Enable masquerading and leave Auto Apply disabled. |
| Access policy | Optionally permits ICMP from the users group to the exit group for diagnostics. |
| DNS configuration | Assigns the DNS servers you choose to the users group when the route is selected. |

The Docker configuration enables NetBird Block LAN Access and does not advertise a LAN route. Review existing DNS groups and internal domains before adding a new primary DNS configuration.

Setup keys are credentials. Give the exit key one use, a short expiration, automatic membership in the exit group, and non-ephemeral behavior so the peer keeps its identity after restarts. Keep the Docker volume `netbird-exit`; deleting it requires a new setup key and creates a new NetBird peer identity.

## Configuration

The supplied `.env.example` contains the values consumed by Compose:

| Variable | Description |
| --- | --- |
| `NETBIRD_MANAGMENT_URL` | NetBird management URL. The spelling is retained for compatibility with the supplied files. |
| `NETBIRD_EXIT_SETUP_KEY` | One-use setup key created for the Docker exit peer. |
| `NETBIRD_CLIENT_SETUP_KEY` | Optional setup key for `client-compose.yaml`. |
| `VPN_SERVICE_PROVIDER` | `airvpn`. |
| `VPN_TYPE` | `wireguard`. |
| `WIREGUARD_PRIVATE_KEY` | AirVPN WireGuard private key. |
| `WIREGUARD_PRESHARED_KEY` | AirVPN WireGuard preshared key. |
| `WIREGUARD_ADDRESSES` | IPv4 tunnel address and prefix from AirVPN. |
| `SERVER_COUNTRIES` and `SERVER_CITIES` | AirVPN server selection. |
| `FIREWALL_VPN_INPUT_PORTS` | The reserved AirVPN UDP port used by both tunnels. |
| `WIREGUARD_MTU` | Set to `1400` in Compose to avoid observed fragmentation. |
| `TZ` | Container time zone. |

Do not publish `.env` or include it in issue reports. It contains private VPN credentials and a NetBird setup key.

## Validate the path

On a selected NetBird device, compare its public address before and after selecting the route:

```sh
curl -4 https://ifconfig.me/ip
netbird networks list
netbird networks select <your-route-name>
curl -4 https://ifconfig.me/ip
```

The second address should match the address reported by Gluetun. To return to the normal path:

```sh
netbird networks deselect <your-route-name>
```

Check IPv6 explicitly. This deployment is IPv4-only, so a public IPv6 response indicates an alternate path that needs to be addressed on the client or surrounding network:

```sh
curl -6 --max-time 10 https://ifconfig.me/ip
```

For a disposable validation peer, create a second one-use setup key assigned to the users group, put it in `NETBIRD_CLIENT_SETUP_KEY`, and start the optional client:

```sh
docker compose -f client-compose.yaml up -d
docker compose -f client-compose.yaml exec netbird-client netbird networks select <your-route-name>
docker compose -f client-compose.yaml exec netbird-client wget -qO- --timeout=10 https://ifconfig.me/ip
```

## Operations

View status and logs:

```sh
docker compose ps
docker compose logs --tail 60 gluetun
docker compose logs --tail 60 netbird
```

Restart NetBird or recreate Gluetun after changing its environment:

```sh
docker compose restart netbird
docker compose up -d --force-recreate gluetun
```

Stop the stack without deleting the saved peer identity:

```sh
docker compose down
docker compose up -d
```

Avoid `docker compose down -v` unless you intend to delete the Docker identities. A used setup key cannot register a replacement identity.

## Security model and limitations

The exit path is enforced while the NetBird route is selected and the client remains connected. A user who deselects the route or stops NetBird can use that device's ordinary internet connection; devices that must never do so need local or network-level enforcement.

IPv6 is disabled rather than tunneled. The VPN-only firewall is designed to blackhole traffic during provider loss, but each deployment should repeat its own outage and DNS checks before being used as a strict isolation boundary.

The stack has no published Docker host ports. The reserved AirVPN UDP port is used inside the provider tunnel for NetBird connectivity.

## Repository layout

```text
compose.yaml          Main namespace, Gluetun, and NetBird services
client-compose.yaml   Optional disposable validation client
vpn-init.sh           Startup, routing, stale-rule cleanup, and isolation rules
post-rules.txt        Empty Gluetun post-firewall hook
.env.example          Configuration template
gluetun/              Gluetun server metadata
setup-guide.md        First-time dashboard-based installation guide
scripts/               Optional measurement and maintenance helpers
evidence/              Development test evidence, not required at runtime
```

## Troubleshooting

If Gluetun is unhealthy, verify the AirVPN keys, tunnel address, server selection, and reserved port, then inspect `docker compose logs gluetun` without sharing secrets.

If NetBird does not register, verify that the setup key is valid, unused, assigned to the exit group, and present as `NETBIRD_EXIT_SETUP_KEY` in `.env`.

If the route is missing, verify that the device belongs to the users group, the route is enabled, and the exit peer is connected. If the route is selected but traffic fails, confirm that Gluetun is healthy and that `vpn-init.sh` and `post-rules.txt` are beside `compose.yaml`.

## References

- [NetBird exit nodes](https://docs.netbird.io/use-cases/remote-access/exit-nodes)
- [NetBird CLI](https://docs.netbird.io/get-started/cli)
- [Gluetun AirVPN configuration](https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/airvpn.md)
- [Gluetun WireGuard options](https://github.com/qdm12/gluetun-wiki/blob/main/setup/options/wireguard.md)
