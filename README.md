# Chroot_Ubuntu
A chroot for Android devices with turnip drivers



For first time installations you should read the information bellow.









This Chroot contains:
Ubuntu 24.04
Mesa from github.com/lfdevs/mesa-for-android-container
a default User created named "user" with password set as "root"
Firefox-esr is installed


1 - To create the container and load it first run: "./.shortcuts/4-load_ubuntu_snapshot.sh" script (This will install dependencies create /data/local/ubuntu and move all file inside this folder)

For a quick test you can run "./.shortcuts/1-ubuntu.sh" and check that everything works
If you want to use the cmd "su" you as a use you must run "sudo su" instead of just "su"

2 - If you want to rename the default user as well as change its default password ("root") you should follow the next steps

3 - After Ubuntu load script finishes run "./.shortcuts/2-safe_mode.sh" (This can also be used as a way to login as root without any android mounts)

4 - While in Safe Mode run the script "rename_user.sh" present in home folder of root user

5 - After your user has been renamed now you must manually edit the launch script indicating the new username.
While in termux as a normal user  run "nano .shortcuts/1-ubuntu.sh"

Edit the following line: "export DEFINED_USERNAME=user"

Replace user with the exact new user name you just defined in the rename script

Press Ctrl + X to save it under the same name as before.

6 - If you want to save this changes you just made to the user and the startup script run "./.shortcuts/3-save_ubuntu_snapshot.sh" this will create a new backup in termux home dir and rename the older one into the same folder.
