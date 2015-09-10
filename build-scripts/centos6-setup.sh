set -x
set -e 

yum update -y
yum install openssh-server openssh-clients cloud-init acpid ntp wget openssl
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


cat << EOF > /etc/cloud/cloud.cfg.d/99_cloudstack.cfg
datasource:
  CloudStack: {}
  None: {}
datasource_list:
  - CloudStack
EOF

sed -i 's,disable_root: 1,disable_root: 0,' /etc/cloud/cloud.cfg
sed -i 's,ssh_pwauth:   0,ssh_pwauth:   1,' /etc/cloud/cloud.cfg
sed -i 's,name: cloud-user,name: root,' /etc/cloud/cloud.cfg

# non-blocking resizefs, should be done in background
sed -i '/resize_rootfs_tmp/aresize_rootfs: noblock' /etc/cloud/cloud.cfg


mkdir -p /var/lib/cloud/scripts/per-boot
cat > /var/lib/cloud/scripts/per-boot/10_cloud-set-guest-password << "EOF"
#!/bin/bash
#
# Init file for Password Download Client
#
# chkconfig: 345 98 02
# description: Password Download Client

# Modify this line to specify the user (default is root)
user=root

# Add your DHCP lease folders here
DHCP_FOLDERS="/var/lib/dhclient/* /var/lib/dhcp3/* /var/lib/dhcp/*"
password_received=0
file_count=0
error_count=0

for DHCP_FILE in $DHCP_FOLDERS
do
	if [ -f $DHCP_FILE ]
	then
		file_count=$((file_count+1))
		PASSWORD_SERVER_IP=$(grep dhcp-server-identifier $DHCP_FILE | tail -1 | awk '{print $NF}' | tr -d '\;')

		if [ -n "$PASSWORD_SERVER_IP" ]
		then
			logger -t "cloud" "Found password server IP $PASSWORD_SERVER_IP in $DHCP_FILE"
			logger -t "cloud" "Sending request to password server at $PASSWORD_SERVER_IP"
			password=$(wget -q -t 3 -T 20 -O - --header "DomU_Request: send_my_password" $PASSWORD_SERVER_IP:8080)
			password=$(echo $password | tr -d '\r')

			if [ $? -eq 0 ]
			then
				logger -t "cloud" "Got response from server at $PASSWORD_SERVER_IP"

				case $password in
				
				"")					logger -t "cloud" "Password server at $PASSWORD_SERVER_IP did not have any password for the VM"
									continue
									;;
				
				"bad_request")		logger -t "cloud" "VM sent an invalid request to password server at $PASSWORD_SERVER_IP"
									error_count=$((error_count+1))
									continue
									;;
									
				"saved_password") 	logger -t "cloud" "VM has already saved a password from the password server at $PASSWORD_SERVER_IP"
									continue
									;;
									
				*)					logger -t "cloud" "VM got a valid password from server at $PASSWORD_SERVER_IP"
									password_received=1
									break
									;;
									
				esac
			else
				logger -t "cloud" "Failed to send request to password server at $PASSWORD_SERVER_IP"
				error_count=$((error_count+1))
			fi
		else
			logger -t "cloud" "Could not find password server IP in $DHCP_FILE"
			error_count=$((error_count+1))
		fi
	fi
done

if [ "$password_received" == "0" ]
then
	if [ "$error_count" == "$file_count" ]
	then
		logger -t "cloud" "Failed to get password from any server"
		exit 1
	else
		logger -t "cloud" "Did not need to change password."
		exit 0
	fi
fi

logger -t "cloud" "Changing password ..."
echo $user:$password | chpasswd
						
if [ $? -gt 0 ]
then
	usermod -p `mkpasswd -m SHA-512 $password` $user
		
	if [ $? -gt 0 ]
	then
		logger -t "cloud" "Failed to change password for user $user"
		exit 1
	else
		logger -t "cloud" "Successfully changed password for user $user"
	fi
fi
						
logger -t "cloud" "Sending acknowledgment to password server at $PASSWORD_SERVER_IP"
wget -t 3 -T 20 -O - --header "DomU_Request: saved_password" $PASSWORD_SERVER_IP:8080
exit 0
EOF

chmod +x /var/lib/cloud/scripts/per-boot/10_cloud-set-guest-password


cat > /var/lib/cloud/scripts/per-boot/20_cloud-set-guest-sshkey << "EOF"
#!/bin/bash 
#
# cloud-set-guest-sshkey    SSH Public Keys Download Client
#
# chkconfig: 2345 98 02
# description: SSH Public Keys Download Client
#
# Modify this line to specify the user (default is root)
user=root

# Add your DHCP lease folders here
DHCP_FOLDERS="/var/lib/dhclient/* /var/lib/dhcp3/* /var/lib/dhcp/*"

keys_received=0
file_count=0

for DHCP_FILE in $DHCP_FOLDERS; do
    if [ -f $DHCP_FILE ]; then
        file_count=$((file_count+1))
        SSHKEY_SERVER_IP=$(grep dhcp-server-identifier $DHCP_FILE | tail -1 | awk '{print $NF}' | tr -d '\;')

        if [ -n $SSHKEY_SERVER_IP ]; then
            logger -t "cloud" "Sending request to ssh key server at $SSHKEY_SERVER_IP"

            publickey=$(wget -t 3 -T 20 -O - http://$SSHKEY_SERVER_IP/latest/public-keys 2>/dev/null)

            if [ $? -eq 0 ]; then
                logger -t "cloud" "Got response from server at $SSHKEY_SERVER_IP"
                keys_received=1
                break
            fi
        else
            logger -t "cloud" "Could not find ssh key server IP in $DHCP_FILE"
        fi
    fi
done

# did we find the keys anywhere?
if [ "$keys_received" == "0" ]; then
    logger -t "cloud" "Failed to get ssh keys from any server"
    exit 1
fi

# set ssh public key
homedir=$(grep ^$user /etc/passwd|awk -F ":" '{print $6}')
sshdir=$homedir/.ssh
authorized=$sshdir/authorized_keys

if [ ! -e $sshdir ]; then
    mkdir $sshdir
fi

if [ ! -e $authorized ]; then
    touch $authorized
fi

if [ `grep -c "$publickey" $authorized` == 0 ]; then
        echo "$publickey" >> $authorized
        /sbin/restorecon -R $homedir/.ssh
fi
exit 0
EOF

chmod +x /var/lib/cloud/scripts/per-boot/20_cloud-set-guest-sshkey

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

passwd --expire root
history -c
unset HISTFILE

