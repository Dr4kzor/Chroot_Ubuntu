## make sure we have mount-utils installed
apt install mount-utils

## kill stuff that might be still runnning
pkill -f xfce
pkill -f pulseaudio
pkill -f termux-x11

## Unmount all android related stuff
sudo umount -l /data/local/ubuntu/proc 2>/dev/null
sudo umount -l /data/local/ubuntu/sys 2>/dev/null
sudo umount -l /data/local/ubuntu/dev/pts 2>/dev/null
sudo umount -l /data/local/ubuntu/dev 2>/dev/null
sudo umount -l /data/local/ubuntu/sdcard 2>/dev/null
sudo umount -l /data/local/ubuntu/tmp/.X11-unix 2>/dev/null
sudo umount -l /data/local/ubuntu/tmp/pulse 2>/dev/null

## Copy our shortcuts into ROOTFS so we save them
sudo rm /data/local/ubuntu/opt/.shortcuts -R
sudo cp ~/.shortcuts /data/local/ubuntu/opt/ -r

## Just in case lets make a backup of the previous snapshot
cp ubuntu-backup.tar.gz old_snapshot_ubuntu-backup.tar.gz

## Save ROOTFS into home dir
sudo tar --numeric-owner --xattrs --acls -czpf ubuntu-backup.tar.gz \
--exclude=/data/local/ubuntu/proc \
--exclude=/data/local/ubuntu/sys \
--exclude=/data/local/ubuntu/dev \
--exclude=/data/local/ubuntu/run \
--exclude=/data/local/ubuntu/tmp \
/data/local/ubuntu


## Fix backup permissions
sudo chmod 766 ubuntu-backup.tar.gz
