## Update Termux
echo "Updating Termux packages!"
echo
echo
apt update
apt upgrade -y


## Setup Storage
termux-setup-storage


## Install dependencies of chroot Ubuntu
apt install tsu x11-repo
apt install termux-x11-nightly pulseaudio mount-utils


## Install curl to download load script and rootfs
echo
echo
echo "Installing CURL!"
echo
echo
apt install curl -y


## Download the file for loading the UBUNTU ROOTFS
echo
echo
echo "Downloading the Loading Script!"
curl -LO https://raw.githubusercontent.com/Dr4kzor/Chroot_Ubuntu/main/4-load_ubuntu_snapshot.sh
## Make the loader script executable
chmod +x 4-load_ubuntu_snapshot.sh
echo
echo


## Download the ROOTFS
echo "Downloading Latest UBUNTU ROOTFS from https://github.com/Dr4kzor/Chroot_Ubuntu/releases/latest/download/ubuntu-backup.tar.gz"
curl -L -o ubuntu-backup.tar.gz \
  https://github.com/Dr4kzor/Chroot_Ubuntu/releases/latest/download/ubuntu-backup.tar.gz
echo
echo


## Run Load script
echo "Setting up needed dependencies as well as Unpacking ROOTFS"
./4-load_ubuntu_snapshot.sh
echo
echo

## Remove load script and installer
echo "Removing installer script and temporary load script"
rm 4-load_ubuntu_snapshot.sh
#rm install_ubuntu_chroot.sh
echo
echo


echo "Ubuntu installed at /data/local/ubuntu/"
echo "Termux widget shortcuts available at .shortcuts/"

echo "Please Install Termux-X11 (Mandatory)"
echo "Please Install Termux:Widgets (enables adding shortcut icons to your home screen, requires termux display over apps setting!)"
echo "To start Ubuntu from console use ./.shortcuts/1-ubuntu.sh"
## All needed scripts are now inside .shortcuts/
echo
echo
echo "By default the username is \"user\" and password is \"root\""
echo "If you want to rename the default user follow these steps:"
echo "1 - run ./.shortcuts/2-safe_mode.sh"
echo "2 - run ./rename_user.sh"
echo "3 - in OLD USERNAME type the name \"user\""
echo "4 - type your desired username and password"
echo "5 - exit chroot (DONE!)"
