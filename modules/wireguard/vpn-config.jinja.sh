set -euo pipefail

IPV4={{ ipv4 | shell }}
IPV6={{ ipv6 | shell }}
PORT={{ port | shell }}
ETH={{ eth | shell }}
LF=$'\n'

KEY_PATH={{ persist ~ "/wireguard.key" | shell }}
PUB_PATH={{ persist ~ "/wireguard.pub" | shell }}
PEERS_PATH={{ persist ~ "/peers" | shell }}
FWD_PATH=/etc/nftables/forward.d
PRR_PATH=/etc/nftables/prerouting.d
NEIGHBOUR_PATH={{ neighbour | shell }}
CON_PATH=/run/NetworkManager/system-connections

# parse command line options
[[ "${1:-}" == "--reload" ]] && reload=true || reload=false
! $reload || shift
(( $# == 0 )) || { printf >&2 '[error] unexpected argument "%s"\n' "$1"; exit 1; }

# generate WireGuard keys if not present
[[ -f "$KEY_PATH" ]] || wg genkey | install -m 400 /dev/stdin "$KEY_PATH"
[[ -f "$PUB_PATH" ]] || wg pubkey < "$KEY_PATH" > "$PUB_PATH"

# load private key
privkey="$(< "$KEY_PATH")"

# prepare config strings
forward_conf="" prerouting_conf="" ipv6s=""
read -rd '' wireguard_conf <<END || true
[connection]
type=wireguard
interface-name=wg0

[ipv4]
address1=$IPV4
method=manual

[ipv6]
address1=$IPV6
method=manual

[wireguard]
listen-port=$PORT
private-key=$privkey
END

# add peers
for peer in "$PEERS_PATH"/*.json; do
  [[ -f "$peer" ]] || continue

  # load values from file
  ipv4="$(jq -ser '.[0].ipv4' < "$peer")"
  ipv6="$(jq -ser '.[0].ipv6' < "$peer")"
  key="$(jq -ser '.[0].key' < "$peer")"
  ports_v4="$(jq -ser '.[0].ports_v4 // [] | join(" ")' < "$peer")"
  ports_v6="$(jq -ser '.[0].ports_v6 // [] | join(" ")' < "$peer")"

  # add firewall rules
  for port in $ports_v4; do
    if [[ "$port" == */* ]]; then proto="${port#*/}"; port="${port%%/*}"; else proto='tcp'; fi
    forward_conf+="iif ${ETH} oif wg0 ip daddr ${ipv4} ${proto} dport ${port} accept${LF}"
    prerouting_conf+="iif ${ETH} meta nfproto ipv4 ${proto} dport ${port} dnat to ${ipv4}${LF}"
  done

  for port in $ports_v6; do
    if [[ "$port" == */* ]]; then proto="${port#*/}"; port="${port%%/*}"; else proto='tcp'; fi
    forward_conf+="iif ${ETH} oif wg0 ip6 daddr ${ipv6} ${proto} dport ${port} accept${LF}"
  done

  # add ipv6 for neighbour entry hook
  ipv6s+="${ipv6}${LF}"

  # add WireGuard peer
  wireguard_conf+="${LF}${LF}[wireguard-peer.${key}]${LF}allowed-ips=${ipv4}/32;${ipv6}/128;"
done

# write config files
mkdir -p "$CON_PATH" "$FWD_PATH" "$PRR_PATH"
printf '%s' "$forward_conf" > "$FWD_PATH/wireguard.conf"
printf '%s' "$prerouting_conf" > "$PRR_PATH/wireguard.conf"
printf '%s' "$ipv6s" > "$NEIGHBOUR_PATH"
install -m600 /dev/stdin "$CON_PATH/wg0.nmconnection" <<< "$wireguard_conf"

# reload firewall and NetworkManager if requested
if $reload; then
  nft -f /etc/sysconfig/nftables.conf
  nmcli connection reload && nmcli device reapply wg0
fi
