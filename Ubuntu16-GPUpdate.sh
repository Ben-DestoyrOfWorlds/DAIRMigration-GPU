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

# Clean up
cd
rm -rf cuda*
rm -rf /root/NVIDIA*

apt-get clean

#Ensure changes are written to disk
sync

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
chattr +i /etc/X11/xorg.conf

# Configure VNC
cd
mkdir .vnc
cat <<EOF | tee .vnc/xstartup.turbovnc
/opt/VirtualGL/bin/vglrun startxfce4 &
EOF

chmod +x .vnc/xstartup.turbovnc
touch .vnc/passwd
chown -R $(whoami): .vnc
sudo ln -s /etc/pam.d/passwd /etc/pam.d/turbovnc

cat <<EOF | sudo tee /etc/sysconfig/tvncservers
VNCSERVERS="1:$(whoami)"
VNCSERVERARGS[1]="-securitytypes unixlogin -pamsession -geometry 1240x900 -depth 24"
EOF

sudo update-rc.d tvncserver defaults
sudo systemctl enable tvncserver

# Use networkd instead of network manager
sudo systemctl disable network-manager.service
sudo systemctl enable systemd-networkd.service

reboot
