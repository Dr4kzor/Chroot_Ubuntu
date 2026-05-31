
## Update termux
apt update
apt upgrade
termux-setup-storage
## Install dependencies of chroot Ubuntu
apt install x11-repo
apt remove sudo
apt install tsu



apt install termux-x11-nightly pulseaudio mount-utils


## Kill if running by some weird reason
pkill -f xfce
pkill -f pulseaudio
pkill -f termux-x11

## Unmount the system if it was left running
sudo umount -lR /data/local/ubuntu/proc 2>/dev/null
sudo umount -lR /data/local/ubuntu/sys 2>/dev/null
sudo umount -lR /data/local/ubuntu/dev/pts 2>/dev/null
sudo umount -lR /data/local/ubuntu/dev 2>/dev/null
sudo umount -lR /data/local/ubuntu/sdcard 2>/dev/null
sudo umount -lR /data/local/ubuntu/tmp/.X11-unix 2>/dev/null
sudo umount -lR /data/local/ubuntu/tmp/pulse 2>/dev/null

sudo umount -R /data/local/ubuntu

## Delete old Ubuntu
sudo rm -rf /data/local/ubuntu

## Create dirs for new instalation and mounts
sudo mkdir -p /data/local/ubuntu
sudo mkdir -p /data/local/ubuntu/proc
sudo mkdir -p /data/local/ubuntu/sys
sudo mkdir -p /data/local/ubuntu/dev
sudo mkdir -p /data/local/ubuntu/sdcard

## Fix permissions
sudo mkdir -p /data/local/ubuntu/tmp
sudo chmod 1777 /data/local/ubuntu/tmp

## Extract ROOTFS into /data/local/ubuntu/
sudo tar --numeric-owner --xattrs --acls -xpf ubuntu-backup.tar.gz -C /

## Copy shortcuts of termux widget
mkdir ~/.shortcuts
sudo cp /data/local/ubuntu/opt/.shortcuts ~/ -r
## Fix shortcuts permissions
sudo chmod 777 ~/.shortcuts/ -R

