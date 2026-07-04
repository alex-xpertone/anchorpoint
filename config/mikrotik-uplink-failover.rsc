# =============================================================================
# AnchorPoint VPN — MikroTik hAP ax2 — UPLINK FAILOVER
# Priority:  1) wired ether1   2) venue Wi-Fi (wifi2)   3) phone hotspot (wifi2)
# Run AFTER mikrotik-travel-base.rsc. Replace every <PLACEHOLDER>.
# =============================================================================

# --- 1. TURN wifi2 INTO A WAN STATION (uplink radio) ---
/interface/bridge/port/remove [find interface=wifi2]
/interface/list/member/add interface=wifi2 list=WAN
/interface/wifi/unset wifi2 configuration.mode
/interface/wifi/unset wifi2 configuration.ssid
/interface/wifi/unset wifi2 security.authentication-types
/interface/wifi/unset wifi2 security.passphrase
/interface/wifi/set wifi2 security.ft=no
/interface/wifi/set wifi2 security.ft-over-ds=no

# --- 2. VENUE Wi-Fi profile (priority 2) — type in the hotel/cafe SSID+password ---
/interface wifi security add name=wifi-sec-venue authentication-types=wpa2-psk,wpa3-psk passphrase="<VENUE_WIFI_PASSWORD>"
/interface wifi configuration add name=wifi-cfg-venue mode=station ssid="<VENUE_WIFI_SSID>" security=wifi-sec-venue disabled=no datapath.bridge=none

# --- 3. PHONE HOTSPOT profile (priority 3 / fallback) — type in your hotspot SSID+password ---
/interface wifi security add name=wifi-sec-hotspot authentication-types=wpa2-psk,wpa3-psk passphrase="<PHONE_HOTSPOT_PASSWORD>"
/interface wifi configuration add name=wifi-cfg-hotspot mode=station ssid="<PHONE_HOTSPOT_SSID>" security=wifi-sec-hotspot disabled=no datapath.bridge=none

# --- 4. START ON VENUE, DHCP AT DISTANCE 10 (wired ether1 stays higher priority at distance 1) ---
/interface/wifi set wifi2 configuration=wifi-cfg-venue
/ip/dhcp-client/add interface=wifi2 disabled=no default-route-distance=10 comment="WiFi-WAN-Uplink"
/ip/dhcp-client/set [find interface=ether1] check-gateway=ping

# --- 5. FAILOVER SCRIPTS ---
/system/script/add name="Switch-To-Venue" source={
    :local i "wifi2"; :local h "wifi-cfg-venue"; :local c "";
    /interface/wifi/print where name=$i do={:set c $configuration};
    :if ($c != $h) do={
        :log warning "WAN: switching to Venue Wi-Fi...";
        /interface/wifi/unset $i configuration.mode;
        /interface/wifi/unset $i configuration.ssid;
        /interface/wifi/unset $i security.authentication-types;
        /interface/wifi/set $i configuration=$h;
        :local n 0;
        :while ([/interface/wifi/get $i running]=false && $n<20) do={:set n ($n+1); :delay 1s};
        :if ([/interface/wifi/get $i running]) do={
            /ip/dhcp-client/release [find interface=$i]; :delay 1s; /ip/dhcp-client/renew [find interface=$i];
        }
    }
}
/system/script/add name="Switch-To-Hotspot" source={
    :local i "wifi2"; :local ip "wifi-cfg-hotspot"; :local c "";
    /interface/wifi/print where name=$i do={:set c $configuration};
    :if ($c != $ip) do={
        :log error "WAN: switching to phone hotspot...";
        /interface/wifi/unset $i configuration.mode;
        /interface/wifi/unset $i configuration.ssid;
        /interface/wifi/unset $i security.authentication-types;
        /interface/wifi/set $i configuration=$ip;
        :local n 0;
        :while ([/interface/wifi/get $i running]=false && $n<20) do={:set n ($n+1); :delay 1s};
        :if ([/interface/wifi/get $i running]) do={
            /ip/dhcp-client/release [find interface=$i]; :delay 1s; /ip/dhcp-client/renew [find interface=$i];
        }
    }
}

# --- 6. WATCHDOG: flip to the other wireless uplink when the current one dies ---
/tool/netwatch/add host=8.8.8.8 interval=30s timeout=2s name="WAN-Watchdog" \
    up-script=":log info \"WAN: Internet is UP\"" \
    down-script=":delay 3s; :local i \"wifi2\"; :local vSSID [/interface/wifi/configuration/get [find name=\"wifi-cfg-venue\"] ssid]; :local cSSID [/interface/wifi/get \$i configuration.ssid]; :if (\$cSSID = \$vSSID) do={ /system/script/run Switch-To-Hotspot } else={ /system/script/run Switch-To-Venue }"

# --- 7. Every 15 min, climb back to the preferred venue Wi-Fi ---
/system/scheduler/add name="Probe-Venue" interval=15m on-event="/system/script/run Switch-To-Venue"

/system/script/set [find name="Switch-To-Venue"]   owner=admin policy=read,write,policy,test dont-require-permissions=yes
/system/script/set [find name="Switch-To-Hotspot"] owner=admin policy=read,write,policy,test dont-require-permissions=yes

# --- Optional: WireGuard watchdog that also fixes time before bouncing the tunnel ---
/tool/netwatch/add host=10.0.80.1 interval=1m timeout=2s type=simple name="WG-Watchdog" \
    down-script={
        :local ntpStatus [/system/ntp/client/get status];
        :if ($ntpStatus != "synchronized") do={
            /system/ntp/client/set enabled=no; :delay 1s; /system/ntp/client/set enabled=yes; :delay 10s;
            :set ntpStatus [/system/ntp/client/get status];
        }
        :if ($ntpStatus = "synchronized") do={
            :delay 5s;
            :if ([/ping 10.0.80.1 count=3]=0) do={
                /interface/wireguard/disable wg1; :delay 2s; /interface/wireguard/enable wg1;
            }
        }
    } \
    up-script=":log info \"WG-Watchdog: tunnel UP\""
