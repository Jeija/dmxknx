#!/bin/bash

# To do before running this script:
# * Connect to Archlinux ARM via the serial port or connect the pi to screen + keyboard
# * Connect the pi to a router that is connected to your computer and the internet and runs a
# * dhcp server.
# * login as user: root / password: root
# * pacman -S openssh
# * systemctl enable sshd
# * reboot and login again (as root and still in the serial console / screen + keyboard)
# * ip addr to find out about ip address
# * Login from remote system via ssh root@<raspi_ip> and password root
# * Copy this script over to the pi from the host system:
# *     scp <path_to_this_script> root@<raspi_ip>:/root/fhem_pi_generator.sh (password: root)
# * chmod +x fhem_pi_generator.sh
# * ./fhem_pi_generator.sh
# * Shortly after starting the script, first enter a new password for the root user, then for the
#   technik user
# * Be patient

# Config
SUDO_CONFIG="%wheel ALL=(ALL) NOPASSWD: ALL"
HOSTNAME="saallicht"
FHEM_URL=http://fhem.de/
FHEM_FILENAME=fhem-5.5

# Exit if something fails
set -e

# Add user "technik", prompt for password
useradd -G "wheel" -m -k /etc/skel technik
passwd
passwd technik

# Configure system & Install fhem
echo $HOSTNAME > /etc/hostname

# Run everything from now on with normal privs:
cd /home/technik

# Install FHEM
pacman -Syu base-devel git perl-device-serialport python2 --noconfirm
sed -i "/${SUDO_CONFIG}/ s/# *//" /etc/sudoers
wget $FHEM_URL$FHEM_FILENAME.tar.gz
tar xzf $FHEM_FILENAME.tar.gz
cd $FHEM_FILENAME
make install
cd ..

# Install hidapi
git clone https://github.com/signal11/hidapi.git
cd hidapi/
./bootstrap
./configure
make
make install
cd ..

# Install usbdmx driver
git clone https://github.com/mlba-team/usbdmx.git
cd usbdmx/
make
cp 50-usbdmx.rules /etc/udev/rules.d/
cd ..

# Download dmxknx software and copy all files together
git clone https://github.com/mkuron/dmxknx.git
cp usbdmx/usbdmx.py dmxknx/
cp usbdmx/libusbdmx.so dmxknx/

# Install FHEM config files
cd dmxknx/
cp ./fhem.cfg /opt/fhem/fhem.cfg
cd ..
sed -i "/logfile/d" /opt/fhem/fhem.cfg
sed -i "/Logfile/d" /opt/fhem/fhem.cfg
sed -i '/attr global modpath ./c\attr global modpath /opt/fhem' /opt/fhem/fhem.cfg

# Make a service file for FHEM
FHEM_SERVICE="[Unit]\nDescription=FHEM Perl Server\nAfter=syslog.target network.target\n\n[Service]\nType=forking\nUser=technik\nWorkingDirectory=/opt/fhem\nExecStart=/usr/bin/perl fhem.pl fhem.cfg\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target"
echo -e $FHEM_SERVICE > /etc/systemd/system/fhem.service
chmod u+x /etc/systemd/system/fhem.service
systemctl daemon-reload
systemctl enable fhem

# Make a service file for DMX KNX
DMXKNX_SERVICE="[Unit]\nDescription=DMX KNX Gateway\nAfter=syslog.target network.target\n\n[Service]\nType=forking\nUser=technik\nWorkingDirectory=/home/technik/dmxknx\nExecStart=/usr/bin/python2 saallicht.py\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target"
echo -e $DMXKNX_SERVICE > /etc/systemd/system/dmxknx.service
chmod u+x /etc/systemd/system/dmxknx.service
systemctl daemon-reload
systemctl enable dmxknx

# Make filesystem readonly
FSTAB_VAR="\ntmpfs   /var/log    tmpfs   nodev,nosuid    0   0\ntmpfs   /var/tmp    tmpfs   nodev,nosuid    0   0"
CMDLINE="ipv6.disable=1 avoid_safe_mode=1 selinux=0 plymouth.enable=0 smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p5 ro rootfstype=ext4 elevator=noop rootwait"
echo -e $CMDLINE > /boot/cmdline.txt
rm /etc/resolv.conf
ln -s /tmp/resolv.conf /etc/resolv.conf
echo -e $FSTAB_VAR >> /etc/fstab
systemctl disable systemd-readahead-collect
systemctl disable systemd-random-seed
systemctl disable ntpd

echo "DONE! Now reboot and pray to make it work."
