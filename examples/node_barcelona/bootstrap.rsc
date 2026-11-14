# =============================================================================
# AnchorPoint Mesh — NODE CONFIG  BARCELONA / Barcelona
# Device: MikroTik hAP ax2 (5-port) · RouterOS v7 · full-mesh WireGuard
# -----------------------------------------------------------------------------
# ⚠ VALIDATE ON A ROUTEROS CHR VM OR SPARE hAP BEFORE PRODUCTION. Verify:
#     • wifi VAP syntax (/interface wifi add master-interface=…) on your ROS build
#     • bridge-port removal from the default bridge for ether2..ether5
#     • remove defconf's leftover 192.168.88.x address/DHCP if reset WITH defaults
#     • routing-rule order + lookup-only-in-table (leak-proof) behaviour
#     • each of the 1 tunnels comes up AND return traffic flows
#       both ways (this node exiting via a remote, AND being an exit for remotes)
# -----------------------------------------------------------------------------
# Port map for this node:
#   ether1 = WAN (uplink)
#   ether2 = EXIT via HAMBURG Hamburg (192.168.21.0/24, SSID "AnchorPoint-HAM", UDP 51820)
#   ether3, ether4, ether5 = LOCAL (192.168.20.0/24, SSID "AnchorPoint-BCN")
# =============================================================================

#------------------------------------------------------------------------------
# 0. IDENTITY / TIME / CLOUD / HARDENING
#------------------------------------------------------------------------------
/system identity set name="mesh-barcelona"
/system clock set time-zone-name=UTC
/user set [find name=admin] password="EXAMPLE-ADMIN-PASSWORD-PLACEHOLDER-NOT-REAL"
/system ntp client set enabled=yes
/system ntp client servers add address=pool.ntp.org
/ip cloud set ddns-enabled=yes
/ip cloud force-update
/ip service disable ftp,telnet
/ipv6 settings set disable-ipv6=yes
/disk settings set auto-media-sharing=no auto-smb-sharing=no

#------------------------------------------------------------------------------
# 1. INTERFACE LISTS + WAN (ether1)
#------------------------------------------------------------------------------
/interface list add name=WAN comment="mesh"
/interface list add name=LAN comment="mesh"
/interface list member add interface=ether1 list=WAN
/ip dhcp-client add interface=ether1 disabled=no use-peer-dns=no comment="WAN uplink"

# Detach ether2..ether5 from the default bridge so each role gets its own network.
/interface bridge port remove [find interface=ether2]
/interface bridge port remove [find interface=ether3]
/interface bridge port remove [find interface=ether4]
/interface bridge port remove [find interface=ether5]

#------------------------------------------------------------------------------
# 2. OVERLAY IDENTITY  (stable 10.0.80.x — tunnel source + watchdog target)
#------------------------------------------------------------------------------
/interface bridge add name=bridge-overlay
/ip address add address=10.0.80.2/32 interface=bridge-overlay comment="mesh overlay id"
/interface list member add interface=bridge-overlay list=LAN

#------------------------------------------------------------------------------
# 3. WIREGUARD — one interface per remote (per-exit; unique UDP port per pair)
#    All interfaces share THIS node's single private key (=> one public key).
#------------------------------------------------------------------------------
/interface wireguard add name=wg-hamburg listen-port=51820 mtu=1420 \
    private-key="EXAMPLE-PRIVATE-KEY-PLACEHOLDER-NOT-A-REAL-KEY-DO-NOT-USE" comment="tunnel barcelona<->hamburg"
/interface wireguard peers add interface=wg-hamburg public-key="EXAMPLE-PUBKEY-hamburg-NOT-A-REAL-KEY" \
    endpoint-address=hamburg.example.net endpoint-port=51820 \
    allowed-address=0.0.0.0/0 persistent-keepalive=25s comment="hamburg Hamburg"
/interface list member add interface=wg-hamburg list=LAN
# reach the remote's overlay IP through its tunnel (watchdog + return path).
# pref-src pins the source to THIS node's overlay IP so router-originated probes
# (the netwatch watchdog below) have a valid source — without it RouterOS cannot
# auto-select a source for a /32 via an addressless wg interface and the watchdog
# false-fails, bouncing the tunnel every interval.
/ip route add dst-address=10.0.80.1/32 gateway=wg-hamburg pref-src=10.0.80.2 comment="overlay hamburg"

#------------------------------------------------------------------------------
# 4. LOCAL NETWORK  (ether3, ether4, ether5 + Wi-Fi "AnchorPoint-BCN" -> local ISP)
#------------------------------------------------------------------------------
/interface bridge add name=bridge-local
/interface bridge port add bridge=bridge-local interface=ether3
/interface bridge port add bridge=bridge-local interface=ether4
/interface bridge port add bridge=bridge-local interface=ether5
/interface list member add interface=bridge-local list=LAN
/ip address add address=192.168.20.1/24 interface=bridge-local
/ip pool add name=pool-local ranges=192.168.20.10-192.168.20.254
/ip dhcp-server add name=dhcp-local interface=bridge-local address-pool=pool-local disabled=no
/ip dhcp-server network add address=192.168.20.0/24 gateway=192.168.20.1 dns-server=192.168.20.1
/interface wifi set wifi1 configuration.mode=ap configuration.ssid="AnchorPoint-BCN" \
    security.authentication-types=wpa2-psk,wpa3-psk security.passphrase="EXAMPLE-WIFI-PASSPHRASE-PLACEHOLDER-NOT-REAL" disabled=no
/interface bridge port add bridge=bridge-local interface=wifi1

#------------------------------------------------------------------------------
# 5. EXIT NETWORKS  (one per remote: wired port + matching Wi-Fi VAP)
#------------------------------------------------------------------------------
# --- EXIT via HAMBURG (Hamburg) ---
/interface bridge add name=bridge-hamburg
/interface bridge port add bridge=bridge-hamburg interface=ether2
/interface list member add interface=bridge-hamburg list=LAN
/ip address add address=192.168.21.1/24 interface=bridge-hamburg
/ip pool add name=pool-hamburg ranges=192.168.21.10-192.168.21.254
/ip dhcp-server add name=dhcp-hamburg interface=bridge-hamburg address-pool=pool-hamburg disabled=no
/ip dhcp-server network add address=192.168.21.0/24 gateway=192.168.21.1 dns-server=192.168.21.1
/interface wifi add name=vap-hamburg master-interface=wifi1 configuration.mode=ap \
    configuration.ssid="AnchorPoint-HAM" security.authentication-types=wpa2-psk,wpa3-psk \
    security.passphrase="EXAMPLE-WIFI-PASSPHRASE-PLACEHOLDER-NOT-REAL" disabled=no
/interface bridge port add bridge=bridge-hamburg interface=vap-hamburg

#------------------------------------------------------------------------------
# 6. LEAK-PROOF POLICY ROUTING  (each exit subnet -> its tunnel, NO fallback)
#    + source-NAT exit traffic to THIS node's overlay IP so the remote exit node
#      can route replies straight back down the tunnel (10.0.80.x/32 route above).
#------------------------------------------------------------------------------
/routing table add name=to-hamburg fib
/ip route add dst-address=0.0.0.0/0 gateway=wg-hamburg routing-table=to-hamburg comment="exit hamburg"
/routing rule add src-address=192.168.21.0/24 action=lookup-only-in-table table=to-hamburg comment="leak-proof hamburg"
/ip firewall nat add chain=srcnat action=src-nat to-addresses=10.0.80.2 out-interface=wg-hamburg comment="exit via hamburg: source from overlay"

#------------------------------------------------------------------------------
# 7. NAT (exit-node egress) + MSS clamp + disable FastTrack
#------------------------------------------------------------------------------
# When THIS node is an exit for a remote: remote traffic arrives (src 10.0.80.x)
# and egresses our WAN masqueraded. Also covers local-network internet.
/ip firewall nat add chain=srcnat action=masquerade out-interface-list=WAN comment="mesh WAN masquerade"
/ip firewall mangle add chain=forward action=change-mss new-mss=clamp-to-pmtu passthrough=yes \
    protocol=tcp tcp-flags=syn comment="mesh MSS clamp"
# FastTrack bypasses policy routing + MSS clamp -> disable it (leak risk).
/ip firewall filter set [find comment="defconf: fasttrack"] disabled=yes

#------------------------------------------------------------------------------
# 8. FIREWALL INPUT — accept each pair's WireGuard UDP port on WAN
#------------------------------------------------------------------------------
/ip firewall filter add chain=input action=accept protocol=udp dst-port=51820 \
    in-interface-list=WAN comment="WG barcelona<->hamburg" place-before=0

#------------------------------------------------------------------------------
# 9. SELF-HEALING WATCHDOG  (per tunnel: fix clock, then bounce if truly dead)
#------------------------------------------------------------------------------
/tool netwatch add host=10.0.80.1 interval=1m timeout=2s type=simple name="wg-hamburg-watchdog" \
    up-script=":log info \"mesh: tunnel to hamburg UP\"" \
    down-script=":local s [/system ntp client get status]; :if (\$s != \"synchronized\") do={ /system ntp client set enabled=no; :delay 1s; /system ntp client set enabled=yes; :delay 10s }; :if ([/ping 10.0.80.1 count=3] = 0) do={ :log error \"mesh: hamburg tunnel dead, restarting\"; /interface wireguard disable wg-hamburg; :delay 2s; /interface wireguard enable wg-hamburg }"

# =============================================================================
# END mesh node barcelona.
# Forward these UDP ports on this site's ISP router: 51820
# =============================================================================
