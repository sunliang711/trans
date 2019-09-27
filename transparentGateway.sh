#!/bin/bash
if (($EUID!=0));then
    echo "Need run as root"
    exit 1
fi

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


function getField(){
    name=$1
}

install(){
    # shadowsocks-libev
    if ! command -v ss-tunnel >/dev/null 2>&1;then
        echo "No ss-tunnel,install shadowsocks-libev..."
        apt install shadowsocks-libev -y

        if ! command -v ss-tunnel >/dev/null 2>&1;then
            echo "Install shadowsocks-libev failed."
            exit 1
        fi
    else
        echo "Find ss-tunnel OK"
    fi

    # dnsmasq
    apt install dnsmasq -y
    mv /etc/dnsmasq.conf{,.old}
    cat<<EOF>/etc/dnsmasq.conf
    no-resolv
    server=127.0.0.1#${chinaPort}
EOF
# chinaDNS
link="https://github.com/shadowsocks/ChinaDNS/releases/download/1.3.2/chinadns-1.3.2.tar.gz"
echo "install chinadns to /usr/local/bin ..."
(cd /tmp && curl -LO "$link" && tar xvf chinadns-1.3.2.tar.gz && cd chinadns-1.3.2 && ./configure && make && cp src/chinadns /usr/local/bin)
cp /tmp/chinadns-1.3.2/chnroute.txt .

# ipforward
cat<<EOF>/etc/sysctl.d/ip_forward
net.ipv4.ip_forward=1
EOF
    sysctl -p

# ipset
curl -sL http://f.ip.cn/rt/chnroutes.txt | egrep -v '^$|^#' > cidr_cn
cat<<EOF>ipset.sh
ipset destroy cidr_cn
ipset -N cidr_cn hash:net
EOF
for i in `cat cidr_cn`; do echo ipset -A cidr_cn $i >> ipset.sh; done
chmod +x ipset.sh

}



start(){
    systemctl start dnsmasq
    # ipset
    echo "set ipset ..."
    ./ipset.sh

    #ss-redir
    echo "start ss-redir ..."
    nohup ss-redir -s $serverIp -p $serverPort -b $redirLocalAddress -l $redirLocalPort -k $password -m $method -u &
    #ss-tunnel
    echo "start ss-tunnel"
    nohup ss-tunnel -s $serverIp -p $serverPort -b $tunnelLocalAddress -l $tunnelLocalPort -k $password -m $method -L $tunnelDestAddressPort -u &

    echo "start chinadns ..."
    nohup chinadns -c chnroute.txt -m -p $chinaPort -s "${chinaDns},127.0.0.1:${tunnelLocalPort}" &

    echo "set iptables ..."
    # iptables
    iptables -t nat -N shadowsocks

    iptables -t nat -A shadowsocks -d 0/8 -j RETURN
    iptables -t nat -A shadowsocks -d 127/8 -j RETURN
    iptables -t nat -A shadowsocks -d 10/8 -j RETURN
    iptables -t nat -A shadowsocks -d 169.254/16 -j RETURN
    iptables -t nat -A shadowsocks -d 172.16/12 -j RETURN
    iptables -t nat -A shadowsocks -d 192.168/16 -j RETURN
    iptables -t nat -A shadowsocks -d 224/4 -j RETURN
    iptables -t nat -A shadowsocks -d 240/4 -j RETURN

    #不走代理的局域网设备
    # iptables -t nat -A shadowsocks -s 192.168.2.10 -j RETRUEN
    # ...

    iptables -t nat -A shadowsocks -d $serverIp -j RETURN

    iptables -t nat -A shadowsocks -m set --match-set cidr_cn dst -j RETURN

    iptables -t nat -A shadowsocks ! -p icmp -j REDIRECT --to-ports $redirLocalPort

    iptables -t nat -A OUTPUT ! -p icmp -j shadowsocks
    iptables -t nat -A PREROUTING ! -p icmp -j shadowsocks
}

stop(){
    echo "stop chinadns ..."
    pkill chinadns
    echo "stop ss-redir ..."
    pkill ss-redir
    echo "stop ss-tunnel ..."
    pkill ss-tunnel

    echo "stop dnsmasq ..."
    systemctl stop dnsmasq

    echo "delete iptables rules ..."
    iptables -t nat -D shadowsocks -d 0/8 -j RETURN
    iptables -t nat -D shadowsocks -d 127/8 -j RETURN
    iptables -t nat -D shadowsocks -d 10/8 -j RETURN
    iptables -t nat -D shadowsocks -d 169.254/16 -j RETURN
    iptables -t nat -D shadowsocks -d 172.16/12 -j RETURN
    iptables -t nat -D shadowsocks -d 192.168/16 -j RETURN
    iptables -t nat -D shadowsocks -d 224/4 -j RETURN
    iptables -t nat -D shadowsocks -d 240/4 -j RETURN

    iptables -t nat -D shadowsocks -d $serverIp -j RETURN

    iptables -t nat -D shadowsocks -m set --match-set cidr_cn dst -j RETURN

    iptables -t nat -D shadowsocks ! -p icmp -j REDIRECT --to-ports $redirLocalPort

    iptables -t nat -X shadowsocks
    iptables -t nat -D OUTPUT ! -p icmp -j shadowsocks
    iptables -t nat -D PREROUTING ! -p icmp -j shadowsocks

    echo "delete ipset cidr_cn ..."
    ipset destroy cidr_cn
}


cmd=$1
case $cmd in
    install)
        install
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
esac

#https://medium.com/@oliviaqrs/%E5%88%A9%E7%94%A8shadowsocks%E6%89%93%E9%80%A0%E5%B1%80%E5%9F%9F%E7%BD%91%E7%BF%BB%E5%A2%99%E9%80%8F%E6%98%8E%E7%BD%91%E5%85%B3-fb82ccb2f729
