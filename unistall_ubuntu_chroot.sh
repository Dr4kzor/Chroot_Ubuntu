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

## Unmount Ubuntu recursively in case something was forgoten
sudo umount -R /data/local/ubuntu

## Delete Ubuntu
sudo rm -rf /data/local/ubuntu


echo "UBUNTU UNINSTALLED SUCCESSFULLY!"
