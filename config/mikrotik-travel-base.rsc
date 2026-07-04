# =============================================================================
# AnchorPoint VPN — MikroTik hAP ax2 travel router — BASE configuration
# RouterOS 7.x. Paste into WinBox/WebFig Terminal. Replace every <PLACEHOLDER>.
# This builds the tunnel + the "AnchorPoint Home Network" LAN.
# For the uplink failover (LAN -> Wi-Fi -> hotspot), run mikrotik-uplink-failover.rsc next.
# =============================================================================

# --- 1. TIME (WireGuard needs a correct clock) ---
/system/ntp/client/set enabled=yes
/system/ntp/client/servers/add address=pool.ntp.org
/system/clock/set time-zone-name=Europe/Berlin

# --- 2. WIREGUARD CLIENT (paste your exported home config) ---
/interface/wireguard/wg-import config-string="
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address    = 10.0.80.3/24
DNS        = 10.0.80.1

[Peer]
PublicKey           = <SERVER_PUBLIC_KEY>
Endpoint            = home.example.myfritz.net:443
AllowedIPs          = 0.0.0.0/0,::/0
PersistentKeepalive = 25
"

# --- 3. TRAVEL LAN 192.168.20.0/24 ROUTED THROUGH THE TUNNEL ---
/interface bridge port remove [find interface=ether2]
/interface bridge add name=bridge-vpn
/interface bridge port add bridge=bridge-vpn interface=ether2
/ip address add address=192.168.20.1/24 interface=bridge-vpn

/routing table add name=to-vpn fib
/ip route add dst-address=0.0.0.0/0 gateway=wg1 routing-table=to-vpn
/routing rule add src-address=192.168.20.0/24 action=lookup-only-in-table table=to-vpn
/ip firewall nat add action=masquerade chain=srcnat out-interface=wg1

/ip pool add name=vpn-pool ranges=192.168.20.10-192.168.20.100
/ip dhcp-server add address-pool=vpn-pool interface=bridge-vpn name=dhcp-vpn
/ip dhcp-server network add address=192.168.20.0/24 dns-server=10.0.80.1 gateway=192.168.20.1

# --- 4. MTU / MSS (prevents "connects but nothing loads") ---
/interface wireguard set wg1 mtu=1412
/ip firewall mangle add action=change-mss chain=forward comment="Clamp MSS out" new-mss=1280 out-interface=wg1 protocol=tcp tcp-flags=syn tcp-mss=1281-65535
/ip firewall mangle add action=change-mss chain=forward comment="Clamp MSS in"  new-mss=1280 in-interface=wg1  protocol=tcp tcp-flags=syn tcp-mss=1281-65535

# --- 5. BROADCAST "AnchorPoint Home Network" ---
# 5 GHz on wifi1. NOTE: if you use Wi-Fi/hotspot as an uplink, leave wifi2 for the
# uplink station (see mikrotik-uplink-failover.rsc) and skip the 2.4 GHz AP line.
/interface/wifi/add name=wifi-vpn-5ghz master-interface=wifi1 configuration.ssid="AnchorPoint Home Network" security.passphrase="<HOME_NETWORK_PASSWORD>" security.authentication-types=wpa2-psk,wpa3-psk disabled=no
/interface/bridge/port add bridge=bridge-vpn interface=wifi-vpn-5ghz
# Wired-uplink-only deployments can also broadcast on 2.4 GHz:
# /interface/wifi/add name=wifi-vpn-2ghz master-interface=wifi2 configuration.ssid="AnchorPoint Home Network" security.passphrase="<HOME_NETWORK_PASSWORD>" security.authentication-types=wpa2-psk,wpa3-psk disabled=no
# /interface/bridge/port add bridge=bridge-vpn interface=wifi-vpn-2ghz

# --- 6. HEALTH + ADMIN REACHABILITY ---
/interface list member add interface=bridge-vpn list=LAN
/interface list member add interface=wg1 list=LAN
/ip firewall filter add chain=input action=accept src-address=192.168.20.0/24 comment="Allow WireGuard Admin Access" place-before=[find comment="defconf: drop all not coming from LAN"]

/tool netwatch add host=10.0.80.1 interval=1m type=simple up-script="" down-script="/interface wireguard disable wg1; :delay 2s; /interface wireguard enable wg1"

# --- 7. HYGIENE / LEAK PREVENTION ---
/ip firewall filter set [find comment="defconf: fasttrack"] src-address=!192.168.20.0/24
/ipv6/settings/set disable-ipv6=yes
/disk settings set auto-media-sharing=no auto-smb-sharing=no
/ip service disable ftp,telnet
/interface wifi set [find] security.ft=no .ft-over-ds=no
