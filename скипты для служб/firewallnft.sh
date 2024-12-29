#!/bin/bash

INTERFACE_TOISP="enp0s3"      # Интерфейс в сторону ISP
INTERFACE_Left="enp0s8"  # Интерфейс в сторону офиса LeftP

nft flush ruleset

nft add table ip filter 
nft add chain ip filter INPUT { type filter hook input priority 0 \; policy drop \;   }
nft add rule ip filter INPUT iifname lo counter accept
nft add rule ip filter INPUT iifname $INTERFACE_Left counter accept
nft add rule ip filter INPUT iifname $INTERFACE_TOISP  ip protocol tcp  tcp dport { 80,2022,443 } counter accept
nft add rule ip filter INPUT iifname $INTERFACE_TOISP  ip protocol udp  udp dport 53 counter accept
nft add rule inet filter output ip protocol icmp accept
