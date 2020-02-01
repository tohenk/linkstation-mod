#!/bin/bash

# Parse parameters
if [ $# -eq 0 ]; then
  BUILD_HELP=1
else
  BUILD_ALL=0
  while [ $# -gt 0 ]; do
    case "$1" in
    -h|--help)
      BUILD_HELP=1
      ;;
    --build)
      BUILD_ALL=1
      ;;
    --clean)
      BUILD_CLEAN=1
      ;;
    --config)
      BUILD_CONFIG=1
      ;;
    --kver)
      BUILD_KERNEL_VER=1
      ;;
    --toolchain)
      BUILD_TOOLCHAIN=1
      ;;
    --kernel)
      BUILD_KERNEL=1
      ;;
    --dt)
      BUILD_DT=1
      ;;
    --package)
      BUILD_PACKAGE=1
      ;;
    --download)
      BUILD_DOWNLOAD=1
      ;;
    --update)
      BUILD_UPDATE=1
      ;;
    esac
    shift
  done
fi

[ "x$BUILD_HELP" = "x1" ] && {
  echo "Usage:"
  echo "`basename $0` [options...]"
  echo ""
  echo "Options:"
  echo "--build        Build all (clean, config if not configured, kernel, and, DT)"
  echo "--clean        Clean kernel source dir tree"
  echo "--config       Perform kernel cofiguration"
  echo "--kver         Choose which kernel version to use"
  echo "--toolchain    Configure toolchain to use"
  echo "--kernel       Build kernel images and modules"
  echo "--dt           Build kernel DT"
  echo "--package      Package kernel and modules as tar archive"
  echo "--download     Download kernel source using GIT"
  echo "--update       Update (pull) GIT repository"
  echo ""

  exit 1
}

CDIR=`pwd`
OUTDIR=$CDIR/build
MYDIR=`dirname $0`
MYDIR=`pushd $MYDIR > /dev/null && pwd -P && popd > /dev/null`

. $MYDIR/build-ls-functions.sh
. $MYDIR/build-ls-kernel.cfg

KERNEL_DIR=$MYDIR/linux
KERNEL_BOOT_DIR=$KERNEL_DIR/arch/$LS_KERNEL_ARCH/boot
KERNEL_IMAGE=zImage
KERNEL_OUT=$KERNEL_BOOT_DIR/$KERNEL_IMAGE
KERNEL_DT=$KERNEL_BOOT_DIR/dts/$LS_KERNEL_DT
KERNEL_GIT=${KERNEL_GIT:=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git}
JOB=${LS_KERNEL_JOB:=4}

# Download kernel source
[ "x$BUILD_DOWNLOAD" = "x1" ] && {
  if [ -d "$KERNEL_DIR" ]; then
    echo "Kernel source has been already downloaded, use --update instead."
  else
    mkdir -p "$KERNEL_DIR"
    echo "Cloning from ${KERNEL_GIT}"
    git clone --progress $KERNEL_GIT $KERNEL_DIR
  fi
  exit 0
}

# Check kernel source directory
[ ! -d "$KERNEL_DIR" ] && {
  echo "Kernel source directory $KERNEL_DIR not found."
  exit 1
}
[ ! -d "$KERNEL_DIR/.git" ] && {
  echo "Only support building kernel from GIT source."
  exit 1
}

cd "$KERNEL_DIR"

# Update repository
[ "x$BUILD_UPDATE" = "x1" ] && {
  # save current modification
  CLEAN=`git status | grep "working directory clean"`
  [ -z "$CLEAN" ] && git stash save -a
  # switch to master
  git checkout master
  git pull
  exit 1
}

# Choose kernel version, only show kernel version matched available configs
[ "x$BUILD_KERNEL_VER" = "x1" ] && {
  VERS=()
  CNT=0
  for VER in `cd $MYDIR/config && ls -v`; do
    KVER=`kernel_latest_ver $VER`
    if [ -n "$KVER" ]; then
      CNT=$((CNT+1))
      VERS[$CNT]=${KVER:1}
    fi
  done
  # Show kernel version choices
  if [ $CNT -ge 1 ]; then
    choices VERS "List of available kernel versions" "%d. Linux kernel %s"
    CHOICE=$?
    if [ $CHOICE -ge 1 ]; then
      echo "Kernel version ${VERS[$CHOICE]} selected."
      sed -i -e "s/LS_KERNEL_VERSION=.*/LS_KERNEL_VERSION=${VERS[$CHOICE]}/" $MYDIR/build-ls-kernel.cfg
    fi
  fi
  exit 1
}

# Configure toolchain to use
mkdir -p $MYDIR/toolchain
[ "x$BUILD_TOOLCHAIN" = "x1" ] && {
  TOOLCHAINS=()
  CNT=0
  for TC in `get_toolchain $MYDIR/toolchain`; do
    CNT=$((CNT+1))
    TOOLCHAINS[$CNT]=$TC
  done
  # Show toolchain choices
  if [ $CNT -ge 1 ]; then
    choices TOOLCHAINS "Choose toolchain"
    CHOICE=$?
    if [ $CHOICE -ge 1 ]; then
      echo "Toolchain used ${TOOLCHAINS[$CHOICE]}."
      sed -i -e "s/LS_KERNEL_TOOLCHAIN=.*/LS_KERNEL_TOOLCHAIN=${TOOLCHAINS[$CHOICE]}/" $MYDIR/build-ls-kernel.cfg
    fi
  else
    toolchain_not_found $MYDIR/toolchain
  fi
  exit 1
}

# Check toolchain
if [ -z "$LS_KERNEL_TOOLCHAIN" ]; then
  echo "Toolchain not configured, use --toolchain to configure."
  exit 1
else
  LS_KERNEL_CROSS_COMPILE=`check_toolchain $MYDIR/toolchain $LS_KERNEL_TOOLCHAIN`
  case $? in
    2)
      toolchain_not_found $MYDIR/toolchain
      exit 1
      ;;
    1)
      echo "Invalid toolchain used, use --toolchain to configure."
      exit 1
      ;;
    0)
      ;;
  esac
fi

# Checkout version
DO_CHECKOUT=1
KTAG="v$LS_KERNEL_VERSION"
TAG=`git status | grep "$KTAG"`
[ -n "$TAG" ] && {
  RTAG=${TAG#* at }
  [ "$KTAG" = "$RTAG" ] && DO_CHECKOUT=0
}
[ "$DO_CHECKOUT" = "1" ] && {
  TAG_FOUND=0
  # Check for tag
  for TAG in `git tag -l`; do
    [ "$TAG" = "$KTAG" ] && {
      TAG_FOUND=1
      break
    }
  done
  if [ $TAG_FOUND -eq 0 ]; then
    echo "Tag $KTAG not found in the repository."
    exit 1
  else
    echo "Switching to $KTAG."
    CLEAN=`git status | grep "working directory clean"`
    [ -z "$CLEAN" ] && git stash save -a
    git checkout tags/$KTAG
    # Allow config and patches to use kernel major version
    LS_KERNEL_MAJOR=
    IFS=. read -a VERS <<< "$LS_KERNEL_VERSION"
    if [ ${#VERS[@]} -ge 2 ]; then
      LS_KERNEL_MAJOR=`echo "${VERS[0]}.${VERS[1]}" | sed -e 's/\-rc[0-9]*//g'`
    fi
    # copy .config from template
    for VER in $LS_KERNEL_VERSION $LS_KERNEL_MAJOR; do
      [ -f "$MYDIR/config/$VER" ] && {
        echo "Copying .config from $MYDIR/config/${VER}..."
        cp "$MYDIR/config/$VER" .config
        break
      }
    done
    # apply patches
    if [ "$LS_KERNEL_VERSION" != "$LS_KERNEL_MAJOR" ]; then
      PATCHES="$LS_KERNEL_MAJOR $LS_KERNEL_VERSION"
    else
      PATCHES=$LS_KERNEL_VERSION
    fi
    for VER in $PATCHES; do
      [ -d "$MYDIR/patches/$VER" ] && {
        echo "Applying patches in ${VER}..."
        for PATCH_FILE in `ls $MYDIR/patches/$VER/*.patch`; do
          echo "Applying patch `basename $PATCH_FILE`..."
          git apply $PATCH_FILE
        done
      }
    done
  fi
}

# Build check
[ "x$BUILD_ALL" = "x1" ] && {
  BUILD_CLEAN=1
  BUILD_KERNEL=1
  BUILD_DT=1
}

# Clean everything
[ "x$BUILD_CLEAN" = "x1" ] && {
  make ARCH=$LS_KERNEL_ARCH clean
}

# Check if .config file has been generated
[ ! -f "$KERNEL_DIR/.config" ] && {
  make ARCH=$LS_KERNEL_ARCH $LS_KERNEL_DEFCONFIG
  BUILD_CONFIG=1
}

# Perform kernel configuration
[ "x$BUILD_CONFIG" = "x1" ] && {
  make ARCH=$LS_KERNEL_ARCH menuconfig
}

# Compile kernel image and modules
[ "x$BUILD_KERNEL" = "x1" ] && {
  make ARCH=$LS_KERNEL_ARCH CROSS_COMPILE=$LS_KERNEL_CROSS_COMPILE -j$JOB $KERNEL_IMAGE modules
  [ ! -f "$KERNEL_OUT" ] && {
    echo "Kernel image not found, aborting."
    exit 1
  }
}

# Ignore DTB build if no DTS
if [ ! -f "${KERNEL_DT}.dts" ]; then
  BUILD_DT=0
fi

# Compile DTB
[ "x$BUILD_DT" = "x1" ] && {
  make ARCH=$LS_KERNEL_ARCH CROSS_COMPILE=$LS_KERNEL_CROSS_COMPILE ${LS_KERNEL_DT}.dtb
}

# Build package
[ "x$BUILD_PACKAGE" = "x1" ] && {
  # Check for kernel image
  [ ! -f "$KERNEL_OUT" ] && {
    echo "Package not built, kernel image not found."
    exit 1
  }

  # Check for DTB
  [ -f "${KERNEL_DT}.dts" -a ! -f "${KERNEL_DT}.dtb" ] && {
    echo "Package not built, DTB not found."
    exit 1
  }

  # Prepare outdir
  [ -d "$OUTDIR" ] && rm -rf "$OUTDIR"
  mkdir -p "$OUTDIR" "$OUTDIR/boot"

  # Append DTB first
  [ -f "${KERNEL_DT}.dtb" ] && {
    cat $KERNEL_OUT ${KERNEL_DT}.dtb > ${KERNEL_OUT}.dtb
    KERNEL_OUT=${KERNEL_OUT}.dtb
  }

  # Make kernel image
  mkimage -A $LS_KERNEL_ARCH -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 -n "Linux-$LS_KERNEL_VERSION" -d $KERNEL_OUT $OUTDIR/boot/uImage.buffalo

  # Install kernel modules
  make ARCH=$LS_KERNEL_ARCH INSTALL_MOD_PATH=$OUTDIR modules_install

  # Cleanup modules
  for DIR in `cd $OUTDIR/lib/modules && ls`; do
    MOD_DIR=$OUTDIR/lib/modules/$DIR
    [ -d $MOD_DIR ] && {
      rm $MOD_DIR/{source,build}
    }
  done

  # Package rootfs
  cd "$OUTDIR" && tar --no-acls -czf $CDIR/ls-kernel-${LS_KERNEL_VERSION}.tar.gz *
  [ -f "$CDIR/ls-kernel-${LS_KERNEL_VERSION}.tar.gz" ] && echo "Package $CDIR/ls-kernel-${LS_KERNEL_VERSION}.tar.gz successfully created."
}

# Done
cd "$CDIR"
