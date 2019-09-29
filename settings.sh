#!/bin/bash

chinaPort=5354
chinaDns=114.114.114.114

#ss-redir config
serverName="g2.2simple.dev"
serverIp="$(nslookup $serverName|sed -n '4,$p'|grep Address|head -1|awk -F' ' '{print $2}')"
echo "server ip: $serverIp"
serverPort=40959
password=9313866243
method=aes-256-cfb

redirLocalAddress=0.0.0.0
redirLocalPort=1080
redirMode=tcp_add_udp

#ss-tunnel config
tunnelLocalAddress=0.0.0.0
tunnelLocalPort=5300
tunnelDestAddressPort=8.8.8.8:53
