#!/bin/sh
set -eu
# Runs before Gluetun and before the dependent NetBird service starts.
# A Gluetun-only replacement enters the holder's existing namespace. Remove the
# old Gluetun INPUT/OUTPUT rules before its firewall appends a fresh set. Keep
# NetBird compatibility rules, which are identifiable by wt0 or NETBIRD.
clean_stale_gluetun_rules() {
    binary=$1
    chain=$2
    "$binary" -S "$chain" | while IFS= read -r rule; do
        case "$rule" in
            *wt0*|*NETBIRD*) continue ;;
            "-A $chain "*)
                set -- $rule
                shift 2
                "$binary" -D "$chain" "$@"
                ;;
        esac
    done
}
clean_stale_gluetun_rules iptables INPUT
clean_stale_gluetun_rules iptables OUTPUT
clean_stale_gluetun_rules ip6tables INPUT
clean_stale_gluetun_rules ip6tables OUTPUT

# The main-table lookup suppresses its default route: no bypass to host egress.
if ! ip rule show | grep -q '^99:.*to 100.64.0.0/10 lookup main suppress_prefixlength 0'; then
    ip rule add to 100.64.0.0/10 lookup main suppress_prefixlength 0 priority 99
fi
# Keep the independent guard in place across internal VPN restarts.
iptables -t security -N LAB-VPN-ONLY 2>/dev/null || true
iptables -t security -C LAB-VPN-ONLY ! -o tun0 -j DROP 2>/dev/null || iptables -t security -A LAB-VPN-ONLY ! -o tun0 -j DROP
iptables -t security -C LAB-VPN-ONLY -d 0.0.0.0/8 -j DROP 2>/dev/null || iptables -t security -A LAB-VPN-ONLY -d 0.0.0.0/8 -j DROP
iptables -t security -C LAB-VPN-ONLY -d 10.0.0.0/8 -j DROP 2>/dev/null || iptables -t security -A LAB-VPN-ONLY -d 10.0.0.0/8 -j DROP
iptables -t security -C LAB-VPN-ONLY -d 100.64.0.0/10 -j DROP 2>/dev/null || iptables -t security -A LAB-VPN-ONLY -d 100.64.0.0/10 -j DROP
iptables -t security -C LAB-VPN-ONLY -d 127.0.0.0/8 -j DROP 2>/dev/null || iptables -t security -A LAB-VPN-ONLY -d 127.0.0.0/8 -j DROP
iptables -t security -C LAB-VPN-ONLY -d 169.254.0.0/16 -j DROP 2>/dev/null || iptables -t security -A LAB-VPN-ONLY -d 169.254.0.0/16 -j DROP
iptables -t security -C LAB-VPN-ONLY -d 172.16.0.0/12 -j DROP 2>/dev/null || iptables -t security -A LAB-VPN-ONLY -d 172.16.0.0/12 -j DROP
iptables -t security -C LAB-VPN-ONLY -d 192.168.0.0/16 -j DROP 2>/dev/null || iptables -t security -A LAB-VPN-ONLY -d 192.168.0.0/16 -j DROP
iptables -t security -C LAB-VPN-ONLY -d 224.0.0.0/4 -j DROP 2>/dev/null || iptables -t security -A LAB-VPN-ONLY -d 224.0.0.0/4 -j DROP
iptables -t security -C LAB-VPN-ONLY -d 240.0.0.0/4 -j DROP 2>/dev/null || iptables -t security -A LAB-VPN-ONLY -d 240.0.0.0/4 -j DROP
iptables -t security -C FORWARD -i wt0 -j LAB-VPN-ONLY 2>/dev/null || iptables -t security -A FORWARD -i wt0 -j LAB-VPN-ONLY

# For WireGuard, only Gluetun's provider socket (fwmark 0xca6c) may use
# physical egress. OpenVPN needs physical egress while establishing its tunnel,
# so Gluetun's own firewall handles that provider path.
if [ "${VPN_TYPE:-}" = wireguard ]; then
    iptables -t security -C OUTPUT -o eth0 -m mark ! --mark 0xca6c -j DROP 2>/dev/null || iptables -t security -A OUTPUT -o eth0 -m mark ! --mark 0xca6c -j DROP
fi
exec /gluetun-entrypoint "$@"
