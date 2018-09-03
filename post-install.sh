#!/bin/bash

################################################################################
#
#    original script:
#    https://github.com/extremeshok/xshok-proxmox
#
################################################################################

HOSTNAME=opteron.dszymczuk.pl
HOSTIP=151.80.34.71
MUNINUSER=munin
MUNINPASS=damian


## disable enterprise proxmox repo
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
	echo -e "#deb https://enterprise.proxmox.com/debian stretch pve-enterprise\n" > /etc/apt/sources.list.d/pve-enterprise.list
fi
## enable public proxmox repo
if [ ! -f /etc/apt/sources.list.d/proxmox.list ] && [ ! -f /etc/apt/sources.list.d/pve-public-repo.list ] && [ ! -f /etc/apt/sources.list.d/pve-install-repo.list ] ; then
	echo -e "deb http://download.proxmox.com/debian stretch pve-no-subscription\n" > /etc/apt/sources.list.d/pve-public-repo.list
fi

## Add non-free to sources
sed -i "s/main contrib/main non-free contrib/g" /etc/apt/sources.list

## Install the latest ceph provided by proxmox
echo "deb http://download.proxmox.com/debian/ceph-luminous stretch main" > /etc/apt/sources.list.d/ceph.list

## Refresh the package lists
apt-get update

# ## Fix no public key error for debian repo
apt-get install -y debian-archive-keyring

# ## Update proxmox and install various system utils
apt-get -y dist-upgrade --force-yes
pveam update

# ## Fix no public key error for debian repo
apt-get install -y debian-archive-keyring


# ## Install missing ksmtuned
apt-get install -y ksmtuned
systemctl enable ksmtuned

# Install ceph support
# echo "Y" | pveceph install

## Install common system utilities
apt-get install -y whois wget nano net-tools htop iptraf iotop iftop iperf screen unzip zip software-properties-common curl dialog mlocate build-essential git

## Detect AMD EPYC CPU and install kernel 4.15
if [ "$(cat /proc/cpuinfo | grep -i -m 1 "model name" | grep -i "EPYC")" != "" ]; then
  echo "AMD EPYC detected"
  #Apply EPYC fix to kernel : Fixes random crashing and instability
  if ! cat /etc/default/grub | grep "GRUB_CMDLINE_LINUX_DEFAULT" | grep -q "idle=nomwait" ; then
    echo "Setting kernel idle=nomwait"
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="idle=nomwait /g' /etc/default/grub
    update-grub
  fi
  echo "Installing kernel 4.15"
  apt-get install -y pve-kernel-4.15
fi

## Remove no longer required packages and purge old cached updates
apt-get autoremove -y
apt-get autoclean -y

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

## Detect if this is an OVH server by getting the global IP and checking the ASN
if [ "$(whois -h v4.whois.cymru.com " -t $(curl ipinfo.io/ip 2> /dev/null)" | tail -n 1 | cut -d'|' -f3 | grep -i "ovh")" != "" ] ; then
	echo "Deteted OVH Server, installing OVH RTM (real time monitoring)"
	#http://help.ovh.co.uk/RealTimeMonitoring
	wget ftp://ftp.ovh.net/made-in-ovh/rtm/install_rtm.sh -c -O install_rtm.sh && bash install_rtm.sh && rm install_rtm.sh
fi

## Protect the web interface with fail2ban
apt-get install -y fail2ban
cat > /etc/fail2ban/filter.d/proxmox.conf <<EOF
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
EOF
cat > /etc/fail2ban/jail.d/proxmox <<EOF
[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 3
# 1 hour
bantime = 3600
EOF
## testing
# fail2ban-regex /var/log/daemon.log /etc/fail2ban/filter.d/proxmox.conf

# increase bantime
sed -i "s/bantime  = 600/bantime  = 86400/g" /etc/fail2ban/jail.conf

systemctl enable fail2ban


## Increase vzdump backup speed
sed -i "s/#bwlimit: KBPS/bwlimit: 10240000/" /etc/vzdump.conf

## Bugfix: pve 5.1 high swap usage with low memory usage
 echo "vm.swappiness=10" >> /etc/sysctl.conf
 sysctl -p

## Remove subscription banner
sed -i "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
# create a daily cron to make sure the banner does not re-appear
cat > /etc/cron.daily/proxmox-nosub <<EOF
#!/bin/sh
sed -i "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
EOF
chmod 755 /etc/cron.daily/proxmox-nosub

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
cat <<'EOF' >> /etc/security/limits.conf
* soft     nproc          131072
* hard     nproc          131072
* soft     nofile         131072
* hard     nofile         131072
root soft     nproc          131072
root hard     nproc          131072
root soft     nofile         131072
root hard     nofile         131072
EOF

## Increase kernel max Key limit
cat <<'EOF' > /etc/sysctl.d/60-maxkeys.conf
kernel.keys.root_maxkeys=1000000
kernel.keys.maxkeys=1000000
EOF


## Increafe vzdump size
cat <<'EOF' >> /etc/vzdump.conf

#
# increase snapshot memory
# https://stackoverflow.com/questions/25449019/snapshot-backup-of-25gb-container-openvz-proxmox
#
size: 4096

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
        root /var/cache/munin/www;
        index index.html index.htm;

        # server_name $HOSTNAME www.$HOSTNAME;

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
# apt-get install certbot
# /etc/init.d/nginx stop
# certbot --register-unsafely-without-email -n --standalone --agree-tos -d $HOSTNAME certonly
# cat << EOF >> /etc/crontab
# 30 6 1,15 * * root /usr/bin/certbot renew --quiet --post-hook /usr/local/bin/renew-pve-certs.sh
# EOF

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

HISTSIZE=1000
HISTFILESIZE=2000

export PS1="\[\033[38;5;10m\]\u\[$(tput sgr0)\]\[\033[38;5;15m\]@\[$(tput sgr0)\]\[\033[38;5;11m\]\h\[$(tput sgr0)\]\[\033[38;5;15m\] [\[$(tput sgr0)\]\[\033[38;5;14m\]\w\[$(tput sgr0)\]\[\033[38;5;15m\]] \[$(tput sgr0)\]"
EOF

## Script Finish
echo -e '\033[1;33m Finished....please restart the system \033[0m'