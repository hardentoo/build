#!/bin/bash

NAME=hardentoo
BASE=/mnt/hardentoo
SOURCE=/mnt/hardentoo
TARGET=/mnt/target
GIT=/mnt/git

green="\e[1;32m"
white="\e[1;37m"

_create_base () {

    echo -e "$green>>> Creating base directory for Hardentoo Linux$white"
    sleep 3

    mkdir -p $BASE

    export ROOT=$BASE

    USE="build" emerge --root=$ROOT -O baselayout

    MAKEDEV -d $ROOT/dev console hda input ptmx std sd tty

    emerge --ask --verbose --root=$ROOT -K @system

    echo -e "$green>>> Successfully created base directory for Hardentoo Linux in $ROOT $white"

}

_add_packages () {

    echo -e "$green>>> Adding additional packages $white"

    export ROOT=$BASE

    emerge --ask --verbose --root=$ROOT -K mc dhcpcd 

}

_mount () {
    mount --rbind /dev ${SOURCE}/dev
    mount --make-rslave ${SOURCE}/dev

    #mount -t tmpfs -o nodev,nosuid,noexec none ${SOURCE}/dev/shm
    #mount -t devpts -o rw,relatime,seclabel,gid=5,mode=620,ptmxmode=000 devpts ${SOURCE}/dev/pts
    #mount -t mqueue -o rw,nosuid,nodev,noexec,relatime,seclabel mqueue ${SOURCE}/dev/mqueue

    mount -t tmpfs -o nodev,nosuid,noexec,noatime,size=1536M,nr_inodes=1M,mode=0777 none ${SOURCE}/tmp

    mount -t proc -o defaults none ${SOURCE}/proc

    mount -t sysfs none ${SOURCE}/sys

    #mount  --rbind /usr/portage ${SOURCE}/usr/portage
}

_umount () {

    umount ${SOURCE}/dev/mqueue
    umount ${SOURCE}/dev/pts
    umount ${SOURCE}/dev/shm
    umount ${SOURCE}/dev
    umount ${SOURCE}/tmp
    umount ${SOURCE}/proc
    umount ${SOURCE}/sys
    #umount ${SOURCE}/usr/portage

}

_clear () {

    rm -rf ${TARGET}/squashfs/usr/src/linux*
    rm -rf ${TARGET}/squashfs/var/tmp/portage/*
    rm -rf ${TARGET}/squashfs/var/tmp/genkernel/*
    rm -rf ${TARGET}/squashfs/boot/*
    rm -rf ${TARGET}/squashfs/root/.bash_history
    rm -rf ${TARGET}/squashfs/hardentoo.sh

}


_build () {

    echo -e "$green>>> Starting build Hardentoo Linux ISO$white"
    sleep 3

    echo ">>> Removing old livecd"
    rm -rf $BASE/$NAME.iso
    echo -e "$green>>> OK $white"
    sleep 3

    echo ">>> Umount File Systems"
    _umount 2>/dev/null
    echo -e "$green>>> OK $white"
    sleep 3

    echo ">>> Remove old target"
    mv ${TARGET} ${TARGET}_old >/dev/null 2>&1
    rm -rf ${TARGET}_old
    echo -e "$green>>> OK $white"
    sleep 3

    echo ">>> Copy /boot to target"
    mkdir -p ${TARGET}
    /usr/bin/time -f "%E" rsync --archive --hard-links ${SOURCE}/boot ${TARGET}/
    echo -e "$green>>> OK $white"
    sleep 3

    echo -e ">>> Copy source to target. It will take some time. Relax and make coffee..."
    mkdir -p ${TARGET}/squashfs
    /usr/bin/time -f "%E" rsync --archive --hard-links --links  --one-file-system --human-readable \
    --exclude "*.a" \
    --exclude "tmp/*" \
    --exclude "var/tmp/*" \
    --exclude "var/cache/*" \
    --exclude "*.debug" \
    --exclude "usr/portage/*" \
    --exclude "usr/share/doc/*" \
    --exclude "usr/include/*" \
    --exclude "var/log/*" \
    --exclude "proc/*" \
    --exclude "sys/*" \
    --exclude "usr/src/*" \
    --exclude "boot/*" \
    --exclude "root/.cache/*" \
    --exclude "root/.config/*" \
    --exclude "root/.bash_history" \
    --exclude "root/.local/*" \
    --exclude "hardentoo.sh" \
    ${SOURCE}/ ${TARGET}/squashfs
    echo -e "$green>>> OK $white"
    sleep 3

    echo -e ">>> Clear target"
    _clear
    echo -e "$green>>> OK $white"
    sleep 3

    echo -e ">>> Create mksquashfs"
    mksquashfs ${TARGET}/squashfs/ ${TARGET}/hardentoo.squashfs -comp xz -b 1M -Xdict-size 100% -always-use-fragments -no-duplicates 
    echo -e "$green>>> OK $white"
    sleep 3

    echo -e ">>> Removing target working file"
    rm -rf ${TARGET}/squashfs
    echo -e "$green>>> OK $white"
    sleep 3

    echo -e "$green>>> Squashfs created, exiting...$white"

    return 0

    echo -e ">>> Create iso"
    grub2-mkrescue -o hardentoo.iso ${TARGET}
    echo -e "$green>>> OK $white"
    sleep 3

    echo -e "$green>>> Livecd created, exiting...$white"

}

_make_in_chroot () {

    echo -e "$green>>> Update environment $white"

    env-update
    source /etc/profile

    echo -e "$green>>> Update root password $white"

    passwd root

    mkdir -p /usr/portage

    emerge --sync

    eselect news list
    eselect news read
    eselect news purge --removed once

    eselect profile list
    eselect profile set 15

    echo "Europe/Moscow" > /etc/timezone

    emerge --config sys-libs/timezone-data

    #ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime

    # locales:
    nano -w /etc/locale.gen
    locale-gen
    eselect locale list
    eselect locale set  ru_RU.utf8
    nano -w /etc/env.d/02locale
    env-update && source /etc/profile

    rc-update add consolefont boot
    rc-update add keymaps boot

    install -d /etc/runlevels/hardentoo

    for SERVICE in $(ls /etc/runlevels/default)
    do
    	rc-update add $SERVICE hardentoo
    done

    rc-update add dhcpcd hardentoo

}

_configure () {

    cp -f ${GIT}/etc/conf.d/consolefont ${SOURCE}/etc/conf.d/consolefont
    cp -f ${GIT}/etc/conf.d/keymaps ${SOURCE}/etc/conf.d/keymaps
    cp -f ${GIT}/etc/resolv.conf ${SOURCE}/etc/resolv.conf
    cp -f ${GIT}/etc/inittab ${SOURCE}/etc/inittab

}

_prepare () {

    env-update
    source /etc/profile

    emerge --sync
    eselect news read
    eselect profile set 11
    eselect profile list

    ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime

    emerge --oneshot portage
    emerge --oneshot layman

    emerge -e world

    emerge @_kernel

}

_kernel () {
   export TERM=xterm
   cd /usr/src/linux
   genkernel --splash=natural_gentoo --all-ramdisk-modules all

}

_update_modules () {
   export TERM=xterm
   emerge --oneshot aufs3 virtualbox-modules virtualbox-guest-additions klibc v86d broadcom-sta
}

_update_initramfs () {
   export TERM=xterm
   genkernel --splash=natural_gentoo --all-ramdisk-modules initramfs
}

_update_users () {
   export TERM=xterm
   gpasswd -a gentoo audio
   gpasswd -a gentoo video
   gpasswd -a gentoo users
   gpasswd -a gentoo wheel
}

_update_env () {

  eselect infinality set linux
  eselect lcdfilter set ubuntu

  eselect fontconfig enable 59-google-droid-sans.conf
  eselect fontconfig enable 59-google-droid-sans-mono.conf
  eselect fontconfig enable 59-google-droid-serif.conf
  eselect fontconfig enable 70-no-bitmaps.conf

}

_chroot () {

  TERM=xterm chroot ${SOURCE} /bin/bash --login

}

if [ "x$1" = "x" ]; then
   echo "Usage: hardentoo.sh command"
   echo "Commands:"
   echo "_create_base - create base directory"
   echo "_build - create iso from source directory"
   echo "_mount - mount filesystems to source directory"
   echo "_umount - umount filesystems from source directory"
   echo "_chroot - chroot to source directory"
   echo "Exiting"
   exit
fi

$1
