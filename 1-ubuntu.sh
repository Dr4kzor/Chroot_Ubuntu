#!/system/bin/sh
	pkill -f termux-x11
	pkill -f pulseaudio
	unset LD_PRELOAD


	export DEFINED_USERNAME=user

	## Only if needed
	#su -c "settings put global settings_enable_monitor_phantom_procs false"


	## Set the root directory
	export ROOTFSPATH=/data/local/ubuntu

	## Mount Android into Chroot
	sudo mount -o remount,dev,suid /data
	sudo mount proc -t proc $ROOTFSPATH/proc
	sudo mount sys -t sysfs $ROOTFSPATH/sys
	sudo mount --bind /dev $ROOTFSPATH/dev
	sudo mount --bind /dev/pts $ROOTFSPATH/dev/pts
	sudo mount --bind /sdcard $ROOTFSPATH/sdcard


	## Create and prepare tmp dir
	export DISPLAY=:0
	sudo mkdir -p $ROOTFSPATH/tmp
	sudo mkdir -p $ROOTFSPATH/tmp/pulse
        sudo chmod -R 1777 $ROOTFSPATH/tmp
	export PULSE_RUNTIME_PATH=$PREFIX/var/run/pulse


	echo "Starting Termux-x11..."
        termux-x11 :0 &>/dev/null &sleep 1
	echo ""
        echo -e "Termux-x11 started!"
        echo ""
	#xhost +local:


	## IF pulse audio crashed for any reason, we should just remove all related directory and recreate them
	rm -rf $PREFIX/var/run/pulse
	mkdir -p $PREFIX/var/run/pulse


	## Copy this cookie so that we can login to audio server from chroot
	sudo mkdir /data/local/ubuntu/home/$DEFINED_USERNAME/.config
	sudo rm /data/local/ubuntu/home/$DEFINED_USERNAME/.config/pulse/cookie -r
	sudo cp ~/.config/pulse/cookie /data/local/ubuntu/home/$DEFINED_USERNAME/.config/pulse/cookie


	## Start pulseaudio without tcp socket
	echo ""
	echo "Starting PulseAudio..."
	echo ""
	pulseaudio --start \
  	--exit-idle-time=-1 \
 	--load="module-aaudio-sink" \
	--load="module-native-protocol-unix auth-anonymous=1 socket=$PREFIX/var/run/pulse/native"


	## Mount pulseaudio
	sudo mount --bind  $PREFIX/var/run/pulse $ROOTFSPATH/tmp/pulse
	## Fix pulseaudio permissions
	sudo chmod 777 $ROOTFSPATH/tmp/pulse


	## Mount termux-x11 socket
	sudo mkdir $ROOTFSPATH/tmp/.X11-unix
	sudo chmod 1777 $ROOTFSPATH/tmp/.X11-unix
	sudo mount --bind $PREFIX/tmp/.X11-unix $ROOTFSPATH/tmp/.X11-unix


	## Open Android Termux-X11 APP
	echo "Starting CHROOT UBUNTU"
        echo ""
	echo "Lauching Android Termux-X11 apk"
	echo ""
	am start -n com.termux.x11/com.termux.x11.MainActivity


	#Step 1 - Login as ROOT
	#Step 2 - Login as User and start xfce
	sudo chroot $ROOTFSPATH /bin/su - -c "export DISPLAY=:0
	       #export XDG_RUNTIME_DIR=/tmp
		## Set pulseaudio socket = native
		export PULSE_SERVER=unix:/tmp/pulse/native
                ## Type of Vsync
		export MESA_VK_WSI_PRESENT_MODE=mailbox
                ## Mesa Driver Override
		export MESA_LOADER_DRIVER_OVERRIDE=kgsl
                ## needed according to the docs of this version of mesa 26.2 delevel
		export TU_DEBUG=noconform
		chown $DEFINED_USERNAME:$DEFINED_USERNAME /home/$DEFINED_USERNAME/.config/pulse/cookie
		chmod 600 /home/$DEFINED_USERNAME/.config/pulse/cookie
		su - $DEFINED_USERNAME -c \"export DISPLAY=:0
			## Set pulseaudio socket = native
			export PULSE_SERVER=unix:/tmp/pulse/native
			## Type of Vsync
			export MESA_VK_WSI_PRESENT_MODE=mailbox
			## Mesa Driver Override
			export MESA_LOADER_DRIVER_OVERRIDE=kgsl
			## needed according to the cods of this version of mesa 26.2 delevel
			export TU_DEBUG=noconform
			dbus-launch --exit-with-session startxfce4
			exit
			\"
		"


	## Remove active mounts
	sudo umount -lR $ROOTFSPATH/proc
	sudo umount -lR $ROOTFSPATH/sys
	sudo umount -lR $ROOTFSPATH/sdcard
	sudo umount -lR $ROOTFSPATH/tmp/.X11-unix
	sudo umount -lR $ROOTFSPATH/dev
	pulseaudio --kill
	sudo umount -lR $ROOTFSPATH/tmp/pulse


	## Close Termux-X11
	pkill -f "app_process / com.termux.x11"
	pkill termux-x11
