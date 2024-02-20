#!/bin/bash
# estrogen - Generates a GRUB menu for dracut UEFI images, cause why not?
# Copyright (c) 2024 Kıvılcım L. Öztürk, Efi S. Öztürk, Y. C. Öztürk.
# Licensed under WTFPL
#

# check if the output is a terminal
is_tty() {
	[ -t 1 ]
}

# a global set of colors
# for use in the script
# in the form of an associated array
declare -A ESTROGEN_COLORS
ESTROGEN_COLORS=(
	[black]="\e[0;30m"
	[red]="\e[0;31m"
	[green]="\e[0;32m"
	[yellow]="\e[0;33m"
	[blue]="\e[0;34m"
	[purple]="\e[0;35m"
	[cyan]="\e[0;36m"
	[white]="\e[0;37m"
	[reset]="\e[0m"
)

remove_vars() {
	# remove all the variables we've set
	# if they exist
	unset ESTROGEN_FORCE
	unset ESTROGEN_PURGE
	unset ESTROGEN_UKI_LOCATION
	unset ESTROGEN_MENU_FILE
	unset ESTROGEN_KERNEL_VERSION
	unset ESTROGEN_KERNEL_ARGS
	unset ESTROGEN_VERBOSE
	unset ESTROGEN_COLORS
}

# function for bailing out
bailout() {
	printf "[estrogen] CRITICAL: "
	echo $1 >/dev/fd/2
	exit $2
}

# function for printing errors
log_error() {
	printf "[estrogen] ERROR: "
	echo $1 >/dev/fd/2
}

# function for printing warnings
log_warning() {
	printf "[estrogen] WARNING: "
	echo $1 >/dev/fd/2
}

# function for printing info
log_info() {
	printf "[estrogen] "
	echo $1
}

check_for_perms() {
	# check if we're root
	if [ $(id -u) != 0 ]; then
		bailout "you need to be root for this action you dummy." 1
	fi

	# check if we can create the menu file
	if ! [ -w /etc/grub.d/ ]; then
		bailout "no write permissions to /etc/grub.d/" 2
	fi

	# check if we have write permissions to the UEFI image directory
	if ! [ -w $UEFI_IMAGE_DIR ]; then
		bailout "no write permissions to $UEFI_IMAGE_DIR" 3
	fi

	# check if we have write permissions to the menu file
	if ! [ -w $ESTROGEN_MENU_FILE ]; then
		bailout "no write permissions to $ESTROGEN_MENU_FILE" 4
	fi

	# check if we have dracut installed
	if ! [ -x "$(command -v dracut)" ]; then
		bailout "dracut is not installed" 5
	fi
	
	# check if it is possible to run dracut --uefi
	# (is systemd-boot installed?)
	if ! [ -d /usr/lib/systemd/boot ]; then
		bailout "systemd-boot is not installed" 6
	fi
}

ESTROGEN_MENU_FILE="/etc/grub.d/60_estrogen_dracut_menu"
UEFI_IMAGE_DIR="/boot/efi/EFI/Linux"

if ! [ -e $ESTROGEN_MENU_FILE ]; then
	touch $ESTROGEN_MENU_FILE ||
		bailout "failed to create: $ESTROGEN_MENU_FILE" 6
fi

estrogen_purge_images() {
	echo "[estrogen] Purging existing Dracut UEFI images in $UEFI_IMAGE_DIR"
	rm -vf $(ls -t "$UEFI_IMAGE_DIR"/*.efi | tail -n +4) || true
}

estrogen_gen_images() {
	echo "[estrogen] Running 'dracut --uefi --force --kver $ESTROGEN_KERNEL_VERSION --kmoddir /lib/modules/$ESTROGEN_KERNEL_VERSION/ $ESTROGEN_KERNEL_ARGS'"
	# run dracut with the specified kernel version and kernel arguments
	dracut --uefi --force --kver $ESTROGEN_KERNEL_VERSION \
		   --kmoddir /lib/modules/$ESTROGEN_KERNEL_VERSION/ \
		   $ESTROGEN_KERNEL_ARGS \
		   || bailout "failed to run dracut" 4
}

estrogen_gen_menu() {
	echo '#!/bin/sh'
	echo 'exec tail -n +3 $0'
	echo 'submenu "estrogen - Dracut UEFI Images" {'
	for entry in "$UEFI_IMAGE_DIR"/*.efi; do
		[[ -f "$entry" ]] || continue
		filename=$(basename "$entry")
		echo "    menuentry 'dracut image $filename' {"
		echo "        chainloader (hd0,1)/EFI/Linux/$filename"
		echo "    }"
	done
	echo '}'
}

estrogen_main() {
	echo "[estrogen] Generating dracut images..."
	estrogen_gen_images || bailout "failed to generate Estrogen UEFI images" 5
	echo "[estrogen] Activating menufile"
	chmod +x $ESTROGEN_MENU_FILE || bailout "failed to activate menufile" 7
	echo "[estrogen] Generating GRUB menu for dracut images"

	estrogen_gen_menu >$ESTROGEN_MENU_FILE
	if [ $? != 0 ]; then
		bailout "failed to generate the estrogen dracut submenu" 8
	fi
	echo "[estrogen] reloading GRUB2 configuration"
	update-bootloader || bailout "failed to update GRUB2 configuration" 9
	echo "[estrogen] Submenu generation completed successfully!"
	exit 0
}


parse_cmdline() {
	while [ $# -gt 0 ]; do
		case $1 in
		--force| -f)
			ESTROGEN_FORCE=1
			;;
		--purge| -p)
			ESTROGEN_PURGE=1
			# purge the kernels and exit
			estrogen_purge_images
			exit 0
			;;
		--uki-location | -l)
			shift
			ESTROGEN_UKI_LOCATION=$1
			;;
		--menufile-location | -m)
			shift
			ESTROGEN_MENU_FILE=$1
			;;
		--kernel-version | -k)
			shift
			ESTROGEN_KERNEL_VERSION=$1
			;;
		--verbose | -v)
			ESTROGEN_VERBOSE=1
			;;
		--kernel-args )
			# space seperated list of kernel arguments, until the next switch
			shift
			# join the rest of the arguments with spaces 
			# until the next switch, denoted by a leading dash
			ESTROGEN_KERNEL_ARGS=$(echo $@ | sed -n '/^-/!{p;q}')
			;;
		--help)
		# long and detailed help
			echo "estrogen - Generates a GRUB menu for dracut UEFI images, cause why not?"
			echo "Usage: estrogen [OPTION]"
			echo "Options:"
			echo "  --force, -f    force regeneration of dracut images and GRUB menu"
			echo "  --purge, -p    purge old dracut images and exit"
			echo "  --uki-location, -l    specify the location of the UEFI kernel images"
			echo "  --kernel-version, -k    specify the kernel version to generate dracut images for"
			echo "  --kernel-args    specify kernel arguments to pass to the dracut image"
			echo "  --menufile-location, -m    specify the location of the GRUB menu file"
			echo "  --help     display this help and exit"
			exit 0
			;;
		--version)
			echo "estrogen 0.1"
			exit 0
			;;
		*)
			bailout "unknown option: $1" 2
			;;
		esac
		shift
	done
}