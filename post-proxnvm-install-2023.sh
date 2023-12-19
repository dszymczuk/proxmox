#!/bin/bash

################################################################################
#
#    original script:
#    https://github.com/extremeshok/xshok-proxmox
#
################################################################################


# SET VARIBLES

OS_CODENAME="$(grep "VERSION_CODENAME=" /etc/os-release | cut -d"=" -f 2 | xargs )"
RAM_SIZE_GB=$(( $(vmstat -s | grep -i "total memory" | xargs | cut -d" " -f 1) / 1024 / 1000))
HOSTNAME=proxnvm.dszymczuk.pl
HOSTIP=5.135.143.116

export LANG="pl_PL.UTF-8"
export LC_ALL="pl_PL.UTF-8"


# force APT to use IPv4
echo -e "Acquire::ForceIPv4 \"true\";\\n" > /etc/apt/apt.conf.d/99-xs-force-ipv4

# disable enterprise proxmox repo
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
  sed -i "s/^deb/#deb/g" /etc/apt/sources.list.d/pve-enterprise.list
fi
# enable free public proxmox repo
if [ ! -f /etc/apt/sources.list.d/proxmox.list ] && [ ! -f /etc/apt/sources.list.d/pve-public-repo.list ] && [ ! -f /etc/apt/sources.list.d/pve-install-repo.list ] ; then
  echo -e "deb http://download.proxmox.com/debian/pve ${OS_CODENAME} pve-no-subscription\\n" > /etc/apt/sources.list.d/pve-public-repo.list
fi

# rebuild and add non-free to /etc/apt/sources.list
cat <<EOF > /etc/apt/sources.list
deb https://ftp.debian.org/debian ${OS_CODENAME} main contrib
deb https://ftp.debian.org/debian ${OS_CODENAME}-updates main contrib
# non-free
deb https://httpredir.debian.org/debian/ ${OS_CODENAME} main contrib non-free
# security updates
deb https://security.debian.org/debian-security ${OS_CODENAME}/updates main contrib
EOF

# Refresh the package lists
apt-get update > /dev/null 2>&1

# Remove conflicting utilities
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' purge ntp openntpd systemd-timesyncd

# Fixes for common apt repo errors
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install apt-transport-https debian-archive-keyring ca-certificates curl

# update proxmox and install various system utils
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' dist-upgrade
pveam update

# Install packages which are sometimes missing on some Proxmox installs.
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install zfsutils-linux proxmox-backup-restore-image chrony

# Install common system utilities
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install \
axel \
build-essential \
curl \
dialog \
dnsutils \
dos2unix \
git \
gnupg-agent \
grc \
htop \
iftop \
iotop \
iperf \
ipset \
iptraf \
mlocate \
msr-tools \
nano \
net-tools \
omping \
software-properties-common \
sshpass \
tmux \
unzip \
vim \
vim-nox \
wget \
whois \
zip


## Ensure ksmtuned (ksm-control-daemon) is enabled and optimise according to ram size
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install ksm-control-daemon
if [[ RAM_SIZE_GB -le 16 ]] ; then
    # start at 50% full
    KSM_THRES_COEF=50
    KSM_SLEEP_MSEC=80
elif [[ RAM_SIZE_GB -le 32 ]] ; then
    # start at 60% full
    KSM_THRES_COEF=40
    KSM_SLEEP_MSEC=60
elif [[ RAM_SIZE_GB -le 64 ]] ; then
    # start at 70% full
    KSM_THRES_COEF=30
    KSM_SLEEP_MSEC=40
elif [[ RAM_SIZE_GB -le 128 ]] ; then
    # start at 80% full
    KSM_THRES_COEF=20
    KSM_SLEEP_MSEC=20
else
    # start at 90% full
    KSM_THRES_COEF=10
    KSM_SLEEP_MSEC=10
fi
sed -i -e "s/\# KSM_THRES_COEF=.*/KSM_THRES_COEF=${KSM_THRES_COEF}/g" /etc/ksmtuned.conf
sed -i -e "s/\# KSM_SLEEP_MSEC=.*/KSM_SLEEP_MSEC=${KSM_SLEEP_MSEC}/g" /etc/ksmtuned.conf
systemctl enable ksmtuned





## Detect AMD EPYC and Ryzen CPU and Apply Fixes
if [ "$(grep -i -m 1 "model name" /proc/cpuinfo | grep -i "EPYC")" != "" ]; then
  echo "AMD EPYC detected"
elif [ "$(grep -i -m 1 "model name" /proc/cpuinfo | grep -i "Ryzen")" != "" ]; then
  echo "AMD Ryzen detected"
else
    XS_AMDFIXES="no"
fi

if [ "${XS_AMDFIXES,,}" == "yes" ] ; then
  #Apply fix to kernel : Fixes random crashing and instability
    if ! grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub | grep -q "idle=nomwait" ; then
        echo "Setting kernel idle=nomwait"
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="idle=nomwait /g' /etc/default/grub
        update-grub
    fi
    ## Add msrs ignore to fix Windows guest on EPIC/Ryzen host
    echo "options kvm ignore_msrs=Y" >> /etc/modprobe.d/kvm.conf
    echo "options kvm report_ignored_msrs=N" >> /etc/modprobe.d/kvm.conf

    echo "Installing kernel 5.15"
    /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install pve-kernel-5.15
fi



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
    sed -i "s/#pigz:.*/pigz: 1/" /etc/vzdump.conf
    /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install pigz
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
port = https,http,8006,8007
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 3
# 1 hour
bantime = 86400
findtime = 600
EOF

# cat <<EOF > /etc/fail2ban/jail.local
# [DEFAULT]
# banaction = iptables-ipset-proto4
# EOF
# sed -i "s/bantime  = 600/bantime  = 86400/g" /etc/fail2ban/jail.conf

systemctl enable fail2ban

## Increase vzdump backup speed, enable pigz and fix ionice
sed -i "s/#bwlimit:.*/bwlimit: 0/" /etc/vzdump.conf
sed -i "s/#pigz:.*/pigz: 1/" /etc/vzdump.conf
sed -i "s/#ionice:.*/ionice: 5/" /etc/vzdump.conf

    ## Bugfix: high swap usage with low memory usage
    cat <<EOF > /etc/sysctl.d/99-xs-swap.conf
# Bugfix: high swap usage with low memory usage
vm.swappiness=10
EOF

## Remove subscription banner
if [ -f "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js" ] ; then
  # create a daily cron to make sure the banner does not re-appear
cat <<'EOF' > /etc/cron.daily/xs-pve-nosub
#!/bin/sh
sed -i "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
sed -i "s/checked_command: function(orig_cmd) {/checked_command: function() {} || function(orig_cmd) {/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
EOF
  chmod 755 /etc/cron.daily/xs-pve-nosub
  bash /etc/cron.daily/xs-pve-nosub
fi
# Remove nag @tinof
echo "DPkg::Post-Invoke { \"dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib\.js$'; if [ \$? -eq 1 ]; then { echo 'Removing subscription nag from UI...'; sed -i '/data.status/{s/\!//;s/Active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; }; fi\"; };" > /etc/apt/apt.conf.d/xs-pve-no-nag && apt --reinstall install proxmox-widget-toolkit

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
    cat <<EOF > /etc/sysctl.d/99-xs-maxwatches.conf
# Increase max user watches
fs.inotify.max_user_watches=1048576
fs.inotify.max_user_instances=1048576
fs.inotify.max_queued_events=1048576
EOF
    ## Increase max FD limit / ulimit
    cat <<EOF >> /etc/security/limits.d/99-xs-limits.conf
# Increase max FD limit / ulimit
* soft     nproc          1048576
* hard     nproc          1048576
* soft     nofile         1048576
* hard     nofile         1048576
root soft     nproc          unlimited
root hard     nproc          unlimited
root soft     nofile         unlimited
root hard     nofile         unlimited
EOF
    ## Increase kernel max Key limit
    cat <<EOF > /etc/sysctl.d/99-xs-maxkeys.conf
# Increase kernel max Key limit
kernel.keys.root_maxkeys=1000000
kernel.keys.maxkeys=1000000
EOF
    ## Set systemd ulimits
    echo "DefaultLimitNOFILE=256000" >> /etc/systemd/system.conf
    echo "DefaultLimitNOFILE=256000" >> /etc/systemd/user.conf

    echo 'session required pam_limits.so' >> /etc/pam.d/common-session
    echo 'session required pam_limits.so' >> /etc/pam.d/runuser-l

    ## Set ulimit for the shell user
    echo "ulimit -n 256000" >> /root/.profile


cat <<EOF > /etc/logrotate.conf
daily
su root adm
rotate 7
create
compress
size=10M
delaycompress
copytruncate

include /etc/logrotate.d
EOF
systemctl restart logrotate

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

sed -i "s/#bwlimit:.*/bwlimit: 0/" /etc/vzdump.conf
sed -i "s/#ionice:.*/ionice: 5/" /etc/vzdump.conf


## Optimise Memory
cat <<EOF > /etc/sysctl.d/99-xs-memory.conf
# Memory Optimising
## Bugfix: reserve 1024MB memory for system
vm.min_free_kbytes=1048576
vm.nr_hugepages=72
# (Redis/MongoDB)
vm.max_map_count=262144
vm.overcommit_memory = 1
EOF

## Enable TCP BBR congestion control
cat <<EOF > /etc/sysctl.d/99-xs-kernel-bbr.conf
# TCP BBR congestion control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF


################################################################################
#
# Server monitoring and another soft
#
################################################################################


wget https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian12_all.deb
dpkg -i zabbix-release_6.4-1+debian12_all.deb
apt update  > /dev/null

apt install zabbix-agent -y

sed -i 's/Server=127.0.0.1/# Server=127.0.0.1/g' /etc/zabbix/zabbix_agentd.conf
sed -i 's/ServerActive=127.0.0.1/# ServerActive=127.0.0.1/g' /etc/zabbix/zabbix_agentd.conf

echo -e "\n\nServer=127.0.0.1,51.178.242.2\n\nServerActive=127.0.0.1,51.178.242.2" >> /etc/zabbix/zabbix_agentd.conf

systemctl restart zabbix-agent
systemctl enable zabbix-agent

service zabbix-agent start
service zabbix-agent restart



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


## Remove no longer required packages and purge old cached updates
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' autoremove
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' autoclean


## Script Finish
echo -e '\033[1;33m Finished....please restart the system \033[0m'
