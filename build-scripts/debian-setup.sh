set -x

apt-get update
apt-get upgrade -y
apt-get install -y acpid ntp

cat > /etc/dhcp/dhclient-exit-hooks.d/sethostname <<'EOM'
#!/bin/sh
# dhclient change hostname script for Debian
# /etc/dhcp/dhclient-exit-hooks.d/sethostname

if [ "$reason" != "BOUND" ] && [ "$reason" != "RENEW" ] && [ "$reason" != "REBIND" ] && [ "$reason" != "REBOOT" ]; then
    exit 0
fi

oldhostname=$(hostname -s)
if [ "$oldhostname" = "localhost" ]; then
    echo "Configuring fresh instance with IP $new_ip_address and hostname $new_host_name.$new_domain_name"
    # Rename Host
    echo $new_host_name > /etc/hostname
    hostname -b -F /etc/hostname
    echo $new_host_name > /proc/sys/kernel/hostname

    # Recreate SSH2
    export DEBIAN_FRONTEND=noninteractive
    dpkg-reconfigure openssh-server

    # Update /etc/hosts
    echo 127.0.0.1 localhost > /etc/hosts
    echo "$new_ip_address $new_host_name.$new_domain_name $new_host_name" >> /etc/hosts
    echo >> /etc/hosts
    echo ::1 localhost ip6-localhost ip6-loopback >> /etc/hosts
    echo ff02::1 ip6-allnodes >> /etc/hosts
    echo ff02::2 ip6-allrouters >> /etc/hosts
fi
EOM

chmod 744 /etc/dhcp/dhclient-exit-hooks.d/sethostname

rm -f /etc/udev/rules.d/70*
rm -f /var/lib/dhcp/dhclient.*
rm -f /etc/ssh/*key*
if [ -f /var/log/audit/audit.log ]; then cat /dev/null > /var/log/audit/audit.log; fi
cat /dev/null > /var/log/wtmp 2>/dev/null
logrotate -f /etc/logrotate.conf 2>/dev/null
rm -f /var/log/*-* /var/log/*.gz 2>/dev/null

echo "localhost" > /etc/hostname
hostname -b -F /etc/hostname

passwd --expire root

wget https://raw.githubusercontent.com/shapeblue/cloudstack-scripts/master/cloud-set-guest-password-debian -O /etc/init.d/cloud-set-guest-password-debian
wget https://raw.githubusercontent.com/shapeblue/cloudstack-scripts/master/cloud-set-guest-sshkey-debian -O /etc/init.d/cloud-set-guest-sshkey-debian

chmod +x /etc/init.d/cloud-set-guest-password-debian
chmod +x /etc/init.d/cloud-set-guest-sshkey-debian

update-rc.d cloud-set-guest-password-debian defaults
update-rc.d cloud-set-guest-password-debian enable
update-rc.d cloud-set-guest-sshkey-debian defaults
update-rc.d cloud-set-guest-sshkey-debian enable

history -c
unset HISTFILE

