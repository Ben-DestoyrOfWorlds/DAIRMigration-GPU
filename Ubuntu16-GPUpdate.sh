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
rm -f NVIDIA-GRID-Linux-KVM-410.92-410.91-412.16.zip
rm -f  410.92-410.91-412.16-grid-license-server-release-notes.pdf  
rm -f  410.92-410.91-412.16-grid-license-server-user-guide.pdf  
rm -f  410.92-410.91-412.16-grid-licensing-user-guide.pdf  
rm -f  410.92-410.91-412.16-grid-software-quick-start-guide.pdf  
rm -f  410.92-410.91-412.16-grid-vgpu-oem-qualification-test-plan.pdf  
rm -f  410.92-410.91-412.16-grid-vgpu-user-guide.pdf  
rm -f  410.92-410.91-412.16-kvm-reference-platform-partner-guidelines.pdf  
rm -f  412.16_grid_win10_server2016_64bit_international.exe  
rm -f  412.16_grid_win8_win7_server2012R2_server2008R2_64bit_international.exe  
rm -f  NVIDIA-Linux-x86_64-410.91-vgpu-kvm.run  
rm -f  NVIDIA-Linux-x86_64-410.92-grid.run

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

# Clean up
cd
rm -rf cuda*
rm -rf /root/NVIDIA*

apt-get clean

## You should reboot or start X now.

reboot
