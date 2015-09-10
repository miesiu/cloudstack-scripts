set -x
set -e 

yum update -y
yum install openssh-server openssh-clients acpid ntp wget openssl
rm -rf /etc/ssh/*key*

rm -fv /root/.bash_history
rm -f /var/lib/dhclient/*
rm -fv /etc/udev/rules.d/*-net.rules /etc/udev/rules.d/*persistent*

yum -y clean all
rm -f /root/anaconda-ks.cfg
rm -f /root/install.log
rm -f /root/install.log.syslog
find /var/log -type f -delete

rm -f /var/lib/random-seed 
grubby --update-kernel=ALL --args="crashkernel=0@0 vga=791"

#bz912801
# prevent udev rules from remapping nics
for i in `find /etc/udev/rules.d/ -name "*persistent*"`; do ln -sf /dev/null $i; done

#bz 1011013
# set eth0 to recover from dhcp errors
echo PERSISTENT_DHCLIENT="1" >> /etc/sysconfig/network-scripts/ifcfg-eth0

# no zeroconf
echo NOZEROCONF=yes >> /etc/sysconfig/network

# disable IPv6
#echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
#echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
#the above prevents proper functioning of postfix and possibly others and don't want to start customising their config
echo NETWORKING_IPV6=no >> /etc/sysconfig/network
echo IPV6INIT=no >> /etc/sysconfig/network

cd /etc/rc.d/init.d
wget https://raw.githubusercontent.com/shapeblue/cloudstack-scripts/master/cloud-set-guest-password-centos --no-check-certificate
wget https://raw.githubusercontent.com/shapeblue/cloudstack-scripts/master/cloud-set-guest-sshkey-centos --no-check-certificate
chmod +x cloud-set-guest-password-centos
chmod +x cloud-set-guest-sshkey-centos

chkconfig --add cloud-set-guest-password-centos
chkconfig --add cloud-set-guest-sshkey-centos
chkconfig cloud-set-guest-password-centos on
chkconfig cloud-set-guest-sshkey-centos on

passwd --expire root
history -c
unset HISTFILE

