#!/bin/sh

# Thanks to the Entware-Ng repo developers.
# also a shoutout to Merlin, and other script installer contributers


# Get probable Router name
RNAME=$(uname -a | grep GT-AC5300 | cut -f2 -d" ")

BOLD="\033[1m"
NORM="\033[0m"
INFO="$BOLD Info: $NORM"
ERROR="$BOLD *** Error: $NORM"
WARNING="$BOLD * Warning: $NORM"
INPUT="$BOLD => $NORM"

i=1 # Will count available partitions (+ 1)
cd /tmp || exit

echo -e "$INFO This script will guide you through the Entware installation."
echo -e "$INFO Script modifies \"entware\" folder only on the chosen drive,"
echo -e "$INFO no other data will be changed. Existing installation will be"
echo -e "$INFO replaced with this one. Also some start scripts will be installed,"
echo -e "$INFO the old ones will be saved on Entware partition with name"
echo -e "$INFO like /tmp/mnt/sda1/jffs_scripts_backup.tgz"
echo

case $(uname -m) in
  armv7l)
    PART_TYPES='ext2|ext3|ext4'
    INST_URL='http://bin.entware.net/armv7sf-k3.2/installer/generic.sh'
    ;;
aarch64)
PART_TYPES='ext2|ext3|ext4'
    INST_URL='http://bin.entware.net/aarch64-k3.10/installer/generic.sh'
    ;;
  mips)
    PART_TYPES='ext2|ext3'
    INST_URL='http://pkg.entware.net/binaries/mipsel/installer/installer.sh'
    ;;
  *)
    echo "This is unsupported platform, sorry."
    ;;
esac

# Start Partition Selection, looping greping for mounted partitions

echo -e "$INFO Looking for available partitions..."
for mounted in $(/bin/mount | grep -E "$PART_TYPES" | cut -d" " -f3) ; do
  echo "[$i] --> $mounted"
  eval mounts$i="$mounted"
  i=$((i + 1))
done

# exit if no partitions found.

if [ $i = "1" ] ; then
  echo -e "$ERROR No $PART_TYPES partitions available. Exiting..."
  exit 1					# Error
fi

# read partition number, 0 will exit

echo -en "$INPUT Please enter partition number or 0 to exit\n$BOLD[0-$((i - 1))]$NORM: "
read -r partitionNumber
if [ "$partitionNumber" = "0" ] ; then
  echo -e "$INFO" Exiting...
  exit 0
fi

# parse for legal partition #
 
if [ "$partitionNumber" -gt $((i - 1)) ] ; then
  echo -e "$ERROR Invalid partition number! Exiting..."
  exit 1					# Error
fi

# good partition, build mount path

echo -e "Creating Mount Path -"
eval entPartition=\$mounts"$partitionNumber"
echo -e "$INFO $entPartition selected.\n"
entFolder=$entPartition/entware

# Save copy of mount path to /jffs
echo "DEV=$entFolder" > /jffs/entpath.txt

# Backup "entware" folder and scripts 

if [ -d "$entFolder" ] ; then
  echo -e "$WARNING Found previous installation, saving..."
  mv "$entFolder" "$entFolder-old_$(date +%F_%H-%M)"
fi
echo -e "$INFO Creating $entFolder folder..."
mkdir "$entFolder"

# lets Fix up /opt
# Prepare root directory

# conditionally modify / (root_fs)

if  [ $RNAME == "GT-AC5300" ] ; then # make sure is GT-AC5300
echo -e "$RNAME Router detected, Will Use OPT fixup code -"
if ! [ -L "/opt" ]; then

# Grab mounted drive
DEV=$entPartition 

# Remount / > rw
mount -o remount,rw / 
sleep 1

# Save original Opt_contents

# make temp opt contents
mkdir -p $DEV/opt_sav/
 
# cd to /opt directory, copy contents

cd /opt
cp -raf * $DEV/opt_sav/

# rm opt directory
cd /
rm -rf /opt

# create sym link
ln -fs /tmp/opt opt

# force drive buffers write
sync; sync

# Remount / > ro
mount -o remount,ro /

# end of create symlink
fi

# end of test if GT-AC5300
fi

if [ -d /tmp/opt ] ; then
  echo -e "$WARNING Deleting old /tmp/opt symlink..."
  rm /tmp/opt
fi
echo -e "$INFO Creating /tmp/opt symlink..."
ln -s "$entFolder" /tmp/opt

echo -e "$INFO Creating /jffs scripts backup..."
tar -czf "$entPartition/jffs_scripts_backup_$(date +%F_%H-%M).tgz" /jffs/scripts/* >/dev/nul

echo -e "$INFO Modifying start scripts..."

# Create usbmount script
cat << EOF > /jffs/scripts/script_usbmount.sh
#!/bin/sh

# Grab mounted drive
. /jffs/entpath.txt

RC='/opt/etc/init.d/rc.unslung'

# put opt link in /tmp
cd /tmp
rm opt
ln -sf \$DEV opt

# Enable Swap if there

if [ -f /opt/swap ] ; then
swapon /opt/swap
fi

# Start Services

i=30
until [ -x "\$RC" ] ; do
  i=\$((\$i-1))
  if [ "\$i" -lt 1 ] ; then
    logger "Could not start Entware"
    exit
  fi
  sleep 1
done
\$RC start
EOF

# script set X bit 
chmod +x /jffs/scripts/script_usbmount.sh

# save to Nvram
nvram set script_usbmount="sh /jffs/scripts/script_usbmount.sh"

# create usbumount script

cat << EOF > /jffs/scripts/script_usbumount.sh
# stop services
/opt/etc/init.d/rc.unslung stop
EOF

# script set X bit
chmod +x /jffs/scripts/script_usbumount.sh

# save to Nvram
nvram set script_usbumount="sh /jffs/scripts/script_usbumount.sh"

if [ "$(nvram get jffs2_scripts)" != "1" ] ; then
  echo -e "$INFO Enabling custom scripts and configs from /jffs..."
  nvram set jffs2_scripts=1
fi

# Commit to nvram
nvram commit

# Swap file
while :
do
    clear
    echo Router model `cat "/proc/sys/kernel/hostname"`
    echo "---------"
    echo "SWAP FILE"
    echo "---------"
    echo "Choose swap file size (Highly Recommended)"
    echo "1. 512MB"
    echo "2. 1024MB"
    echo "3. 4096MB (recommended for MySQL Server or PlexMediaServer)"	
    echo "4. Skip this step, I already have a swap file / partition"
    echo "   or I don't want to create one right now"
    read -p "Enter your choice [ 1 - 4 ] " choice
    case "$choice" in
        1) 
            echo -e "$INFO Creating a 512MB swap file..."
            echo -e "$INFO This could take a while, be patient..."
            dd if=/dev/zero of=/opt/swap bs=1024 count=524288
            mkswap /opt/swap
            chmod 0600 /opt/swap
			swapon /opt/swap
            read -p "Press [Enter] key to continue..." readEnterKey
			free
			break
            ;;
        2)
            echo -e "$INFO Creating a 1024MB swap file..."
            echo -e "$INFO This could take a while, be patient..."
            dd if=/dev/zero of=/opt/swap bs=1024 count=1048576
            mkswap /opt/swap
            chmod 0600 /opt/swap
			swapon /opt/swap
            read -p "Press [Enter] key to continue..." readEnterKey
			free
			break
            ;;
        3)
            echo -e "$INFO Creating a 4096MB swap file..."
            echo -e "$INFO This could take a while, be patient..."
            dd if=/dev/zero of=/opt/swap bs=1024 count=5099520
            mkswap /opt/swap
            chmod 0600 /opt/swap
			swapon /opt/swap
            read -p "Press [Enter] key to continue..." readEnterKey
			free
			break
            ;;			
        4)
            free
			break
            ;;
        *)
            echo "ERROR: INVALID OPTION!"			
			echo "Press 1 to create a 512MB swap file"
			echo "Press 2 to create a 1024MB swap file"
			echo "Press 3 to create a 4GB swap file (for Mysql or Plex)"			
			echo "Press 4 to skip swap creation (not recommended)" 
            read -p "Press [Enter] key to continue..." readEnterKey
            ;;
    esac	
done

# do install
wget -qO - $INST_URL | sh

