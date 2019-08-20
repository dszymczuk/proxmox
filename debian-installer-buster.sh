#!/bin/bash


## Manually: 

# nano /etc/default/grub

# GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"

# grub-mkconfig -o /boot/grub/grub.cfg

# cat > /etc/network/interfaces <<EOF
# # The loopback network interface
# # auto lo
# # iface lo inet loopback

# # auto eth0
# # iface eth0 inet static
# # 	address HOSTIP
# # 	netmask 255.255.255.255
# # 	broadcast HOSTIP
# # 	post-up ip route add 151.80.34.254 dev eth0
# # 	post-up ip route add default via 151.80.34.254
# # 	pre-down ip route del 151.80.34.254 dev eth0
# # 	pre-down ip route del default via 151.80.34.254
# EOF

# nano /etc/resolv.conf

# nameserver 213.186.33.99

# reboot


# apt-get -y install openssh-server
# nano /etc/ssh/shhd_config

## uncomment Port
## Change Port to
## uncomment PermitRootLogin
## change prohibit-password to yes

## End of Manually

echo -e '\033[1;32m DEBIAN instalation... \033[0m'

cat > /etc/apt/sources.list <<EOF
#------------------------------------------------------------------------------#
#                   OFFICIAL DEBIAN REPOS
#------------------------------------------------------------------------------#

###### Debian Main Repos
deb http://deb.debian.org/debian/ buster main contrib non-free

deb http://deb.debian.org/debian/ buster-updates main contrib non-free

deb http://deb.debian.org/debian-security buster/updates main

deb http://ftp.debian.org/debian buster-backports main


EOF

cat > /etc/apt/stable.list <<EOF
#------------------------------------------------------------------------------#
#                   OFFICIAL DEBIAN REPOS STABLE
#------------------------------------------------------------------------------#

###### Debian Main Repos
deb http://deb.debian.org/debian/ buster main contrib non-free

deb http://deb.debian.org/debian/ buster-updates main contrib non-free

deb http://deb.debian.org/debian-security buster/updates main

deb http://ftp.debian.org/debian buster-backports main


EOF

cat > /etc/apt/testing.list <<EOF
#------------------------------------------------------------------------------#
#                   OFFICIAL DEBIAN REPOS TESTING
#------------------------------------------------------------------------------#

###### Debian Main Repos
deb http://deb.debian.org/debian/ buster main contrib non-free

deb http://deb.debian.org/debian/ buster-updates main contrib non-free

deb http://deb.debian.org/debian-security buster/updates main

deb http://ftp.debian.org/debian buster-backports main


EOF


# use stable as default release
cat >> /etc/apt/apt.conf.d/99defaultrelease <<EOF
APT::Default-Release "stable";
EOF

apt-get update -y
apt-get upgrade -y

echo "vm.swappiness=10" >> /etc/sysctl.conf
sysctl -p

## Docker pre-install

echo -e '\033[1;32m Software instalation... \033[0m'

apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common openssh-server

sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/g" /etc/ssh/sshd_config


apt-get install -y whois wget nano net-tools htop iptraf iotop iftop iperf screen unzip zip curl dialog mlocate build-essential git

echo -e '\033[1;32m Setup time... \033[0m'

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

echo -e '\033[1;96m Docker instalation... \033[0m'

### Append Docker sources
cat >> /etc/apt/sources.list <<EOF

#------------------------------------------------------------------------------#
#                      UNOFFICIAL  REPOS
#------------------------------------------------------------------------------#

###### 3rd Party Binary Repos
###Docker CE
deb [arch=amd64] https://download.docker.com/linux/debian buster stable
EOF

apt-get update -y

## Docker install
curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -

apt-get update

apt-get install -y docker-ce

groupadd docker

usermod -aG docker damian

## Docker compose install
curl -L https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo -e '\033[1;32m Fail2ban instalation... \033[0m'

## Install fail2ban
apt-get -t testing install fail2ban
sed -i "s/bantime  = 600/bantime  = 86400/g" /etc/fail2ban/jail.conf

echo -e '\033[1;32m Munin with plugins instalation... \033[0m'

## Install munin
apt-get -y install munin-node munin-plugins-extra

## Remove all plugins
rm -rf /etc/munin/plugins/
mkdir -p /etc/munin/plugins/

mkdir -p /usr/local/munin/lib/plugins

pushd /usr/local/munin/lib/plugins
wget https://raw.githubusercontent.com/munin-monitoring/contrib/master/plugins/docker/docker_cpu
wget https://raw.githubusercontent.com/munin-monitoring/contrib/master/plugins/docker/docker_memory
chmod +x /usr/local/munin/lib/plugins/docker_cpu
chmod +x /usr/local/munin/lib/plugins/docker_memory
popd

cat > /etc/munin/plugin-conf.d/docker <<EOF
[docker_cpu]
user root

[docker_memory]
user root
EOF


## Enable plugin which I need
ln -s /usr/share/munin/plugins/cpu /etc/munin/plugins/cpu
ln -s /usr/share/munin/plugins/df /etc/munin/plugins/df
ln -s /usr/share/munin/plugins/diskstats /etc/munin/plugins/diskstats
ln -s /usr/share/munin/plugins/fail2ban /etc/munin/plugins/fail2ban
ln -s /usr/share/munin/plugins/hddtemp_smartctl /etc/munin/plugins/hddtemp_smartctl
ln -s /usr/share/munin/plugins/load /etc/munin/plugins/load
ln -s /usr/share/munin/plugins/memory /etc/munin/plugins/memory
ln -s /usr/share/munin/plugins/munin_stats /etc/munin/plugins/munin_stats
ln -s /usr/share/munin/plugins/open_files /etc/munin/plugins/open_files
ln -s /usr/share/munin/plugins/postfix_mailqueue /etc/munin/plugins/postfix_mailqueue
ln -s /usr/share/munin/plugins/processes /etc/munin/plugins/processes
ln -s /usr/share/munin/plugins/proc_pri /etc/munin/plugins/proc_pri
ln -s /usr/share/munin/plugins/swap /etc/munin/plugins/swap
ln -s /usr/share/munin/plugins/threads /etc/munin/plugins/threads
ln -s /usr/share/munin/plugins/uptime /etc/munin/plugins/uptime
ln -s /usr/share/munin/plugins/users /etc/munin/plugins/users
ln -s /usr/share/munin/plugins/vmstat /etc/munin/plugins/vmstat

## Enable Docker plugins
ln -s /usr/local/munin/lib/plugins/docker_cpu /etc/munin/plugins/docker_cpu
ln -s /usr/local/munin/lib/plugins/docker_memory /etc/munin/plugins/docker_memory

cat >> /etc/munin/munin-node.conf <<EOF

allow ^46\.105\.102\.152$
EOF

/etc/init.d/munin-node restart

echo -e '\033[1;32m Rkhunter instalation... \033[0m'

# Install rkhunter
apt-get install -y rkhunter

sed -i "s/#ALLOW_SSH_ROOT_USER=no/ALLOW_SSH_ROOT_USER=yes/g" /etc/rkhunter.conf
sed -i "s/#MAIL-ON-WARNING=root/MAIL-ON-WARNING=opteron@dszymczuk.pl/g" /etc/rkhunter.conf
## rkhunter --versioncheck
## rkhunter --update
## rkhunter -c -sk

echo -e '\033[1;32m .bashrc configuration \033[0m'

# Config .bashrc
cat > /root/.bashrc <<EOF
export LS_OPTIONS='--color=auto'
eval "\`dircolors\`"
alias ls='ls $LS_OPTIONS'

# Some more alias to avoid making mistakes:
alias rm='rm -i'
# alias cp='cp -i'
# alias mv='mv -i'

HISTSIZE=2000
HISTFILESIZE=5000

alias dockerCleanExited='docker rm $(docker ps --all -q -f status=exited)'
alias dockerStopAll='docker stop $(docker ps -q)'
alias dockerStartAll='docker start $(docker ps --all -q -f status=exited)'
alias dockerRemoveUntaggedImage='docker rmi $(docker images -q -f dangling=true)'
alias dockerRemoveDanglingVolumes='docker volume rm $(docker volume ls -qf dangling=true)'

export PS1="\[\033[38;5;10m\]\u\[$(tput sgr0)\]\[\033[38;5;15m\]@\[$(tput sgr0)\]\[\033[38;5;11m\]\h\[$(tput sgr0)\]\[\033[38;5;15m\] [\[$(tput sgr0)\]\[\033[38;5;14m\]\w\[$(tput sgr0)\]\[\033[38;5;15m\]] \[$(tput sgr0)\]"
EOF

## Script Finish
echo -e '\033[1;33m Finished....please restart the system \033[0m'