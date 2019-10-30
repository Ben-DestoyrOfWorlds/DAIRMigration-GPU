#! /bin/bash -x
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

/etc/init.d/x11-common stop
systemctl stop lightdm.service
/etc/init.d/tvncserver stop

export DEBIAN_FRONTEND=noninteractive

#Blacklist nouveau

cat <<EOF | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
blacklist lbm-nouveau
options nouveau modeset=0
alias nouveau off
alias lbm-nouveau off
EOF

chattr -i /etc/X11/xorg.conf

echo blacklist nouveau | tee -a /etc/modprobe.d/blacklist.conf

rmmod nouveau

echo options nouveau modeset=0 | tee -a /etc/modprobe.d/nouveau-kms.conf

update-initramfs -u

# nvidia drivers, cuda

apt-get update
# Be extra explicit about noninteractive.
DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-extra-virtual linux-headers-generic build-essential unzip dkms

# Install vGPU Driver
echo " ====> Downloading vGPU Driver"
wget -q https://swift-yyc.cloud.cybera.ca:8080/v1/AUTH_8c4974ed39a44c2fabd9d75895f6e28b/cybera_public/NVIDIA-GRID-Linux-KVM-410.92-410.91-412.16.zip
unzip NVIDIA-GRID-Linux-KVM-410.92-410.91-412.16.zip
chmod +x *.run

apt-get install -y nvidia-modprobe

echo " ====> Installing vGPU Driver"
./NVIDIA-Linux-x86_64-410.92-grid.run --dkms -as -k $(uname -r)

# Cleanup NVIDIA
rm -rf *.pdf
rm -rf *.exe
rm -rf *.zip
rm -rf *.run

# Set up licensing
mkdir -p /etc/nvidia
cat << EOF | tee /etc/nvidia/gridd.conf
ServerAddress=nvidia.dair-atir.canarie.ca
ServerPort=7070
FeatureType=2
EnableUI=False
LicenseInterval=1440
EOF

echo " ====> Downloading CUDA"
#10.1 not supported by latest vGPU driver (410.92)
#wget -q https://developer.nvidia.com/compute/cuda/10.1/Prod/local_installers/cuda_10.1.105_418.39_linux.run
wget -q https://developer.nvidia.com/compute/cuda/10.0/Prod/local_installers/cuda_10.0.130_410.48_linux
chmod +x cuda_*

echo " ====> Installing CUDA"
./cuda* --silent --toolkit --samplespath=/usr/local/cuda/samples

cat << EOF | tee /etc/ld.so.conf.d/ld-library.conf
# Add CUDA to LD
/usr/local/cuda/lib64
EOF

ldconfig

#Ensure changes are written to disk
sync
# This script is based on https://github.com/cybera/openstack-images/blob/6de2d7a91d05e8725823a13555a53aff4c9325f3/packer_files/UbuntuvGPU.sh

sudo apt-get install -y xubuntu-desktop libglu1-mesa-dev libx11-dev freeglut3-dev mesa-utils dictionaries-common

#TurboVNC and VirtualGL
cd
mkdir t
pushd t
wget -q https://sourceforge.net/projects/virtualgl/files/2.6.1/virtualgl_2.6.1_amd64.deb/download -O virtualgl_2.6.1_amd64.deb
wget -q https://sourceforge.net/projects/turbovnc/files/2.2.1/turbovnc_2.2.1_amd64.deb/download -O turbovnc_2.2.1_amd64.deb
sudo dpkg -i *.deb
popd
sudo rm -rf t

sudo chmod +s /usr/lib/libdlfaker.so
sudo chmod +s /usr/lib/libvglfaker.so

sudo /opt/VirtualGL/bin/vglserver_config -config +s +f +t

cat <<EOF | sudo tee /etc/X11/xorg.conf
Section "DRI"
        Mode 0666
EndSection
Section "ServerLayout"
    Identifier     "Layout0"
    Screen      0  "Screen0"
    InputDevice    "Keyboard0" "CoreKeyboard"
    InputDevice    "Mouse0" "CorePointer"
EndSection
Section "Files"
EndSection
Section "InputDevice"
    # generated from default
    Identifier     "Mouse0"
    Driver         "mouse"
    Option         "Protocol" "auto"
    Option         "Device" "/dev/psaux"
    Option         "Emulate3Buttons" "no"
    Option         "ZAxisMapping" "4 5"
EndSection
Section "InputDevice"
    # generated from default
    Identifier     "Keyboard0"
    Driver         "kbd"
EndSection
Section "Monitor"
    Identifier     "Monitor0"
    VendorName     "Unknown"
    ModelName      "Unknown"
    HorizSync       28.0 - 33.0
    VertRefresh     43.0 - 72.0
    Option         "DPMS"
EndSection
Section "Device"
    Identifier     "Device0"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BusID          "0:6:0"
EndSection
Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
    Monitor        "Monitor0"
    DefaultDepth    24
    SubSection     "Display"
        Virtual     1280 1024
        Depth       24
    EndSubSection
EndSection
EOF
sudo chattr +i /etc/X11/xorg.conf

sudo update-rc.d tvncserver defaults
sudo systemctl enable tvncserver

# Use networkd instead of network manager
sudo systemctl disable network-manager.service
sudo systemctl enable systemd-networkd.service

# Make xfce4 the default terminal as gnome-terminal doesn't work via VNC
sudo update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal.wrapper


# Clean up
cd
rm -rf cuda*
rm -rf /root/NVIDIA*

apt-get clean

## You should reboot or start X now.

reboot
