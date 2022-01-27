#!/bin/bash

################################################################################
#
#    original script:
#    https://github.com/extremeshok/xshok-proxmox
#
################################################################################

HOSTNAME=proxnvm.dszymczuk.pl
HOSTIP=5.135.143.116
MUNINUSER=munin
MUNINPASS=damian

export LANG="pl_PL.UTF-8"
export LC_ALL="pl_PL.UTF-8"

## disable enterprise proxmox repo
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
	echo -e "#deb https://enterprise.proxmox.com/debian buster pve-enterprise\n" > /etc/apt/sources.list.d/pve-enterprise.list
fi
## enable public proxmox repo
if [ ! -f /etc/apt/sources.list.d/proxmox.list ] && [ ! -f /etc/apt/sources.list.d/pve-public-repo.list ] && [ ! -f /etc/apt/sources.list.d/pve-install-repo.list ] ; then
	echo -e "deb http://download.proxmox.com/debian buster pve-no-subscription\n" > /etc/apt/sources.list.d/pve-public-repo.list
fi

## Add non-free to sources
sed -i "s/main contrib/main non-free contrib/g" /etc/apt/sources.list

## Install the latest ceph provided by proxmox
echo "deb http://download.proxmox.com/debian/ceph-luminous buster main" > /etc/apt/sources.list.d/ceph.list

## Refresh the package lists
apt-get update > /dev/null

## Remove conflicting utilities
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' purge ntp openntpd chrony ksm-control-daemon

## Fix no public key error for debian repo
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install debian-archive-keyring

## Update proxmox and install various system utils
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' dist-upgrade
pveam update

# ## Fix no public key error for debian repo
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install debian-archive-keyring


# ## Install missing ksmtuned
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install ksmtuned
systemctl enable ksmtuned
systemctl enable ksm

# Install ceph support
# echo "Y" | pveceph install

## Install common system utilities
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install whois omping tmux sshpass wget axel nano pigz net-tools htop iptraf iotop iftop iperf vim vim-nox unzip zip software-properties-common aptitude curl dos2unix dialog mlocate build-essential git ipset


## Detect AMD EPYC CPU and install kernel 4.15
if [ "$(grep -i -m 1 "model name" /proc/cpuinfo | grep -i "EPYC")" != "" ]; then
  echo "AMD EPYC detected"
  #Apply EPYC fix to kernel : Fixes random crashing and instability
  if ! grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub | grep -q "idle=nomwait" ; then
    echo "Setting kernel idle=nomwait"
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="idle=nomwait /g' /etc/default/grub
    update-grub
  fi
  echo "Installing kernel 4.15"
  /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install pve-kernel-4.15
fi

## Remove no longer required packages and purge old cached updates
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' autoremove
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' autoclean

## Disable portmapper / rpcbind (security)	
systemctl disable rpcbind	
systemctl stop rpcbind

## Set Timezone to UTC and enable NTP
timedatectl set-timezone Europe/Warsaw
echo > /etc/systemd/timesyncd.conf <<EOF
[Time]
NTP=0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org
FallbackNTP=0.debian.pool.ntp.org 1.debian.pool.ntp.org 2.debian.pool.ntp.org 3.debian.pool.ntp.org
RootDistanceMaxSec=5
PollIntervalMinSec=32
PollIntervalMaxSec=2048
EOF
service systemd-timesyncd start
timedatectl set-ntp true 

## Set pigz to replace gzip, 2x faster gzip compression
cat  <<EOF > /bin/pigzwrapper
#!/bin/sh
PATH=/bin:\$PATH
GZIP="-1"
exec /usr/bin/pigz "\$@"
EOF
mv -f /bin/gzip /bin/gzip.original
cp -f /bin/pigzwrapper /bin/gzip
chmod +x /bin/pigzwrapper
chmod +x /bin/gzip

## Detect if this is an OVH server by getting the global IP and checking the ASN
if [ "$(whois -h v4.whois.cymru.com " -t $(curl ipinfo.io/ip 2> /dev/null)" | tail -n 1 | cut -d'|' -f3 | grep -i "ovh")" != "" ] ; then
  echo "Deteted OVH Server, installing OVH RTM (real time monitoring)"
  #http://help.ovh.co.uk/RealTimeMonitoring
  #wget ftp://ftp.ovh.net/made-in-ovh/rtm/install_rtm.sh -c -O install_rtm.sh && bash install_rtm.sh && rm install_rtm.sh
  wget -qO - https://last-public-ovh-infra-yak.snap.mirrors.ovh.net/yak/archives/apply.sh | OVH_PUPPET_MANIFEST=distribyak/catalog/master/puppet/manifests/common/rtmv2.pp bash
fi

## Protect the web interface with fail2ban
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install fail2ban
# shellcheck disable=1117
cat <<EOF > /etc/fail2ban/filter.d/proxmox.conf
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
EOF
cat <<EOF > /etc/fail2ban/jail.d/proxmox.conf
[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 3
# 1 hour
bantime = 86400
EOF
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
banaction = iptables-ipset-proto4
EOF
sed -i "s/bantime  = 600/bantime  = 86400/g" /etc/fail2ban/jail.conf
systemctl enable fail2ban
##testing
#fail2ban-regex /var/log/daemon.log /etc/fail2ban/filter.d/proxmox.conf

## Increase vzdump backup speed, enable pigz and fix ionice
sed -i "s/#bwlimit:.*/bwlimit: 0/" /etc/vzdump.conf
sed -i "s/#pigz:.*/pigz: 1/" /etc/vzdump.conf
sed -i "s/#ionice:.*/ionice: 5/" /etc/vzdump.conf

## Bugfix: pve 5.1 high swap usage with low memory usage
echo "vm.swappiness=10" >> /etc/sysctl.conf
sysctl -p

## Bugfix: reserve 512MB memory for system
echo "vm.min_free_kbytes = 524288" >> /etc/sysctl.conf
sysctl -p

## Remove subscription banner
if [ -f "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js" ] ; then
  sed -i "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
  # create a daily cron to make sure the banner does not re-appear
  cat <<'EOF' > /etc/cron.daily/proxmox-nosub
#!/bin/sh
# eXtremeSHOK.com Remove subscription banner
sed -i "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
EOF
  chmod 755 /etc/cron.daily/proxmox-nosub
fi

## Pretty MOTD
if ! grep -q https "/etc/motd" ; then
cat > /etc/motd.new <<'EOF'

########  ########   #######  ##     ## ##     ##  #######  ##     ## 
##     ## ##     ## ##     ##  ##   ##  ###   ### ##     ##  ##   ##  
##     ## ##     ## ##     ##   ## ##   #### #### ##     ##   ## ##   
########  ########  ##     ##    ###    ## ### ## ##     ##    ###    
##        ##   ##   ##     ##   ## ##   ##     ## ##     ##   ## ##   
##        ##    ##  ##     ##  ##   ##  ##     ## ##     ##  ##   ##  
##        ##     ##  #######  ##     ## ##     ##  #######  ##     ## 

EOF
  cat /etc/motd >> /etc/motd.new
  mv /etc/motd.new /etc/motd
fi

## Increase max user watches
# BUG FIX : No space left on device
echo 1048576 > /proc/sys/fs/inotify/max_user_watches
echo "fs.inotify.max_user_watches=1048576" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

## Increase max FD limit / ulimit
cat <<EOF >> /etc/security/limits.conf
# eXtremeSHOK.com Increase max FD limit / ulimit
* soft     nproc          256000
* hard     nproc          256000
* soft     nofile         256000
* hard     nofile         256000
root soft     nproc          256000
root hard     nproc          256000
root soft     nofile         256000
root hard     nofile         256000
EOF

## Enable TCP BBR congestion control
cat <<EOF > /etc/sysctl.d/10-kernel-bbr.conf
# eXtremeSHOK.com
# TCP BBR congestion control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

## Increase kernel max Key limit
cat <<EOF > /etc/sysctl.d/60-maxkeys.conf
# eXtremeSHOK.com
# Increase kernel max Key limit
kernel.keys.root_maxkeys=1000000
kernel.keys.maxkeys=1000000
EOF

## Set systemd ulimits
echo "DefaultLimitNOFILE=256000" >> /etc/systemd/system.conf
echo "DefaultLimitNOFILE=256000" >> /etc/systemd/user.conf
echo 'session required pam_limits.so' | tee -a /etc/pam.d/common-session-noninteractive
echo 'session required pam_limits.so' | tee -a /etc/pam.d/common-session
echo 'session required pam_limits.so' | tee -a /etc/pam.d/runuser-l

## Set ulimit for the shell user
cd ~ && echo "ulimit -n 256000" >> .bashrc ; echo "ulimit -n 256000" >> .profile


## Increase vzdump size
cat <<'EOF' >> /etc/vzdump.conf

#
# increase snapshot memory
# https://stackoverflow.com/questions/25449019/snapshot-backup-of-25gb-container-openvz-proxmox
#
size: 4096
pigz: 1

EOF


################################################################################
#
# Server monitoring and another soft
#
################################################################################

## Install nginx
apt-get -y install nginx

## Remove default host
rm -f /etc/nginx/sites-enabled/default

## Install and set htpasswd
apt-get -y install apache2-utils
mkdir -p /.htpasswd
htpasswd -b -c /.htpasswd/munin $MUNINUSER $MUNINPASS

## Install munin
apt-get -y install munin munin-node munin-plugins-extra 

cat > /etc/munin/munin.conf <<EOF
dbdir /var/lib/munin
htmldir /var/cache/munin/www
logdir /var/log/munin
rundir  /var/run/munin
tmpldir /etc/munin/templates
includedir /etc/munin/munin-conf.d


[$HOSTNAME]
  address 127.0.0.1
  use_node_name yes
EOF


## Munin plugins
## Show list
## /usr/sbin/munin-node-configure --suggest
## Enable
## ln -s /usr/share/munin/plugins/cpuspeed /etc/munin/plugins/cpuspeed
## Disable
## rm /etc/munin/plugins/cpuspeed

## Remove all plugins
rm -rf /etc/munin/plugins/
mkdir -p /etc/munin/plugins/

## Enable plugin which I need
ln -s /usr/share/munin/plugins/cpu /etc/munin/plugins/cpu
ln -s /usr/share/munin/plugins/df /etc/munin/plugins/df
ln -s /usr/share/munin/plugins/diskstats /etc/munin/plugins/diskstats
ln -s /usr/share/munin/plugins/fail2ban /etc/munin/plugins/fail2ban
ln -s /usr/share/munin/plugins/hddtemp_smartctl /etc/munin/plugins/hddtemp_smartctl
ln -s /usr/share/munin/plugins/load /etc/munin/plugins/load
ln -s /usr/share/munin/plugins/memory /etc/munin/plugins/memory
ln -s /usr/share/munin/plugins/munin_stats /etc/munin/plugins/munin_stats
ln -s /usr/share/munin/plugins/nfs_client /etc/munin/plugins/nfs_client
ln -s /usr/share/munin/plugins/open_files /etc/munin/plugins/open_files
ln -s /usr/share/munin/plugins/postfix_mailqueue /etc/munin/plugins/postfix_mailqueue
ln -s /usr/share/munin/plugins/processes /etc/munin/plugins/processes
ln -s /usr/share/munin/plugins/proc_pri /etc/munin/plugins/proc_pri
ln -s /usr/share/munin/plugins/swap /etc/munin/plugins/swap
ln -s /usr/share/munin/plugins/threads /etc/munin/plugins/threads
ln -s /usr/share/munin/plugins/uptime /etc/munin/plugins/uptime
ln -s /usr/share/munin/plugins/users /etc/munin/plugins/users
ln -s /usr/share/munin/plugins/vmstat /etc/munin/plugins/vmstat


## Add virtual host for munin

cat > /etc/nginx/sites-enabled/munin <<EOF
server {
  server_name $HOSTNAME www.$HOSTNAME;
  listen 80 ;
  access_log /var/log/nginx/access.log;
  return 301 https://\$host\$request_uri;
}

server {
  server_name $HOSTNAME www.$HOSTNAME;
  listen 443 ssl http2 ;
  access_log /var/log/nginx/access.log;
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers 'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:!DSS';

  ssl on;
  ssl_certificate /etc/pve/local/pveproxy-ssl.pem;
  ssl_certificate_key  /etc/pve/local/pveproxy-ssl.key;

  root /var/cache/munin/www;
        index index.html index.htm;

  location / {
                try_files \$uri \$uri/ /index.html;
                autoindex on;
                allow all;
                auth_basic "Restricted";
                auth_basic_user_file /.htpasswd/munin;
        }
}

server {
  listen 80;
  server_name localhost;
  location /nginx_status {
    stub_status on;
    access_log off;
    allow 127.0.0.1;
    deny all;
  }   
}
EOF


## Add SSL certificate
apt-get install -y certbot
/etc/init.d/nginx stop
certbot --register-unsafely-without-email -n --standalone --agree-tos -d $HOSTNAME certonly

cp /etc/letsencrypt/live/$HOSTNAME/fullchain.pem /etc/pve/local/pveproxy-ssl.pem
cp /etc/letsencrypt/live/$HOSTNAME/privkey.pem /etc/pve/local/pveproxy-ssl.key

cat > /usr/local/bin/renew-pve-certs.sh <<EOF
cp /etc/letsencrypt/live/$HOSTNAME/fullchain.pem /etc/pve/local/pveproxy-ssl.pem
cp /etc/letsencrypt/live/$HOSTNAME/privkey.pem /etc/pve/local/pveproxy-ssl.key

systemctl restart pveproxy
EOF

chmod +x /usr/local/bin/renew-pve-certs.sh


cat << EOF >> /etc/crontab
30 6 1,15 * * root /usr/bin/certbot renew --quiet --post-hook /usr/local/bin/renew-pve-certs.sh
EOF

systemctl restart pveproxy

## Restart nginx and munin
/etc/init.d/nginx restart 
/etc/init.d/munin-node restart

## Config .bashrc
cat > /root/.bashrc <<EOF
export LS_OPTIONS='--color=auto'
eval "\`dircolors\`"
alias ls='ls $LS_OPTIONS'

# Some more alias to avoid making mistakes:
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

HISTSIZE=2000
HISTFILESIZE=5000

export PS1="\[\033[38;5;10m\]\u\[$(tput sgr0)\]\[\033[38;5;15m\]@\[$(tput sgr0)\]\[\033[38;5;11m\]\h\[$(tput sgr0)\]\[\033[38;5;15m\] [\[$(tput sgr0)\]\[\033[38;5;14m\]\w\[$(tput sgr0)\]\[\033[38;5;15m\]] \[$(tput sgr0)\]"
EOF

## Script Finish
echo -e '\033[1;33m Finished....please restart the system \033[0m'
