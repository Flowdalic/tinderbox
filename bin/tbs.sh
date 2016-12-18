#!/bin/sh
#
# set -x

# setup a new tinderbox image
#
# typical call:
#
# $> echo "sudo ~/tb/bin/tbs.sh" | at now + 10 min

# due to using sudo we need to define the path to $HOME
#
tbhome=/home/tinderbox

#############################################################################
#
# functions
#

# create a (r)andomized (U)SE (f)lag (s)ubset
#
function rufs()  {
  allflags="
    aes-ni alisp alsa aqua avcodec avformat btrfs bugzilla bzip2 cairo cdb
    cdda cddb cgi cgroups clang compat consolekit contrib corefonts csc
    cups curl dbus dec_av2 declarative designer dnssec dot drmkms dvb dvd
    ecc egl eglfs emacs evdev exif ext4 extra extraengine fax ffmpeg fitz
    fluidsynth fontconfig fortran fpm freetds ftp gcj gd gif git glamor
    gles gles2 gnomecanvas gnome-keyring gnuplot gnutls go gpg graphtft
    gstreamer gtk gtk2 gtk3 gtkstyle gudev gui gzip haptic havege hdf5
    help hpn ibus icu imap imlib infinality inifile introspection ipv6
    isag jadetex javascript javaxml jpeg kerberos kvm lapack latex ldap
    libinput libkms libvirtd llvm logrotate lua lvm lzma mad mbox
    mdnsresponder-compat melt midi mikmod minimal minizip mng mod modplug
    mono mp3 mp4 mpeg mpeg2 mpeg3 mpg123 mpi mssql mta multimedia mysql
    mysqli ncurses networking nscd nss obj objc odbc offensive ogg ois
    opencv openexr opengl openmpi openssl opus osc pam pcre16 perl php
    pkcs11 plasma plotutils png policykit postgres postproc postscript
    printsupport pulseaudio pwquality pypy python qemu qml qt5 rdoc
    rendering ruby sasl scripts scrypt sddm sdl secure-delete
    semantic-desktop server smartcard smime smpeg snmp sockets source
    sourceview spice sql sqlite sqlite3 ssh ssh-askpass ssl svc svg
    swscale system-cairo system-ffmpeg system-harfbuzz system-icu
    system-jpeg system-libevent system-libs system-libvpx system-llvm
    system-sqlite szip tcl tcpd theora thinkpad threads timidity tk tls
    tools tracepath traceroute truetype udev udisks ufed uml usb usbredir
    utils uxa v4l v4l2 vaapi vala vdpau video vim vlc vorbis vpx wav
    wayland webgl webkit webstart widgets wma wxwidgets X x264 x265 xa xcb
    xetex xinerama xinetd xkb xml xmlreader xmp xscreensaver xslt xvfb
    xvmc xz zenmap ziffy zip zlib
  "
  # formatter: echo "$allflags" | xargs -n 1 | sort -u | xargs -s 76 | sed 's/^/    /g'
  #

  # (m)ask a flag with a likelihood of 1/m
  # or (s)et it with a likelihood of s/m
  # else don't mention it
  #
  m=50  # == 2%
  s=4   # == 8%

  for f in $(echo $allflags)
  do
    let "r = $RANDOM % $m"
    if [[ $r -eq 0 ]]; then
      echo -n " -$f"    # mask it

    elif [[ $r -le $s ]]; then
      echo -n " $f"     # set it
    fi
  done
}


# ... and get the current stage3 file name
#
function ComputeImageName()  {
  if [[ "$profile" = "hardened/linux/amd64" ]]; then
    name="hardened"
    stage3=$(grep "^20....../hardened/stage3-amd64-hardened-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  elif [[ "$profile" = "hardened/linux/amd64/no-multilib" ]]; then
    name="hardened-no-multilib"
    stage3=$(grep "^20....../hardened/stage3-amd64-hardened+nomultilib-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  elif [[ "$profile" = "default/linux/amd64/13.0/no-multilib" ]]; then
    name="13.0-no-multilib"
    stage3=$(grep "^20....../stage3-amd64-nomultilib-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  elif [[ "$(basename $profile)" = "systemd" ]]; then
    name="$(basename $(dirname $profile))-systemd"
    stage3=$(grep "^20....../systemd/stage3-amd64-systemd-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  else
    name="$(basename $profile)"
    stage3=$(grep "^20....../stage3-amd64-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')
  fi

  if [[ "$libressl" = "y" ]]; then
    name="$name-libressl"
  fi

  name="$name-$keyword"
}


# download, verify and unpack the stage3 file
#
function UnpackStage3()  {
  b=$(basename $stage3)
  f=/var/tmp/distfiles/$b
  if [[ ! -f $f || ! -s $f ]]; then
    wget --quiet --no-clobber $wgethost/$wgetpath/$stage3{,.DIGESTS.asc} --directory-prefix=/var/tmp/distfiles || exit 4
  fi

  gpg --quiet --verify $f.DIGESTS.asc || exit 4

  mkdir $name           || exit 4
  cd $name              || exit 4
  tar xjpf $f --xattrs  || exit 4
}


# repos.d/* , make.conf and other stuff
#
function CompilePortageFiles()  {
  mkdir -p                  usr/local/portage/{metadata,profiles}
  echo 'masters = gentoo' > usr/local/portage/metadata/layout.conf
  echo 'local' >            usr/local/portage/profiles/repo_name
  chown -R portage:portage  usr/local/portage/

  # the local repository rules always
  #
  mkdir -p     etc/portage/repos.conf/
  cat << EOF > etc/portage/repos.conf/default.conf
[DEFAULT]
main-repo = gentoo

[gentoo]
priority = 1

[tinderbox]
priority = 2

#[foo]
#priority = 3

[local]
priority = 99

EOF

  cat << EOF > etc/portage/repos.conf/gentoo.conf
[gentoo]
location  = /usr/portage
auto-sync = no

EOF

  cat << EOF > etc/portage/repos.conf/tinderbox.conf
[tinderbox]
location  = /tmp/tb/data/portage
masters   = gentoo
auto-sync = no

EOF

  cat << EOF > etc/portage/repos.conf/foo.conf
#[foo]
#location  = /usr/local/foo
#auto-sync = yes
#sync-type = git
#sync-uri  = https://anongit.gentoo.org/git/proj/foo.git

EOF

  cat << EOF > etc/portage/repos.conf/local.conf
[local]
location  = /usr/local/portage
masters   = gentoo
auto-sync = no

EOF

  # compile make.conf now together
  #
  m=etc/portage/make.conf
  chmod a+w $m

  sed -i  -e '/^CFLAGS="/d'       \
          -e '/^CXXFLAGS=/d'      \
          -e '/^CPU_FLAGS_X86=/d' \
          -e '/^USE=/d'           \
          -e '/^PORTDIR=/d'       \
          -e '/^PKGDIR=/d'        \
          -e '/^#/d'              \
          -e '/^DISTDIR=/d'       \
          $m

# no -Werror=implicit-function-declaration, please see https://bugs.gentoo.org/show_bug.cgi?id=602960
#
  cat << EOF >> $m
CFLAGS="-O2 -pipe -march=native -Wall"
CXXFLAGS="-O2 -pipe -march=native"

USE="
  pax_kernel xtpax -cdinstall -oci8 -bindist
  ssp

$(echo $flags | xargs -s 78 | sed 's/^/  /g')
"

ACCEPT_KEYWORDS=$( [[ "$keyword" = "unstable" ]] && echo '~amd64' || echo 'amd64' )
$(/usr/bin/cpuinfo2cpuflags-x86)
PAX_MARKINGS="XT"

$( [[ "$multilib" = "y" ]] && echo '#ABI_X86="32 64"' )

L10N="$(grep -v -e '^$' -e '^#' /usr/portage/profiles/desc/l10n.desc | cut -f1 -d' ' | sort --random-sort | head -n $(($RANDOM % 10)) | sort | xargs)"

ACCEPT_LICENSE="*"

MAKEOPTS="-j1"
NINJAFLAGS="-j1"

EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --color=n --nospinner --tree --quiet-build"
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"
CLEAN_DELAY=0

ALSA_CARDS="hda-intel"
INPUT_DEVICES="evdev synaptics"
VIDEO_CARDS="intel i965"

FEATURES="xattr preserve-libs parallel-fetch ipc-sandbox network-sandbox test-fail-continue -news"

DISTDIR="/var/tmp/distfiles"
PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

GENTOO_MIRRORS="$wgethost rsync://mirror.netcologne.de/gentoo/ ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/gor.bytemark.co.uk/gentoo/ rsync://ftp.snt.utwente.nl/gentoo"

EOF

  mkdir tmp/tb  # mount point of the tinderbox directory of the host

  # create portage directories and symlinks (becomes effective by the bind-mount of ~/tb)
  #
  mkdir usr/portage
  mkdir var/tmp/{distfiles,portage}

  for d in package.{accept_keywords,env,mask,unmask,use} env patches profile
  do
    mkdir     etc/portage/$d 2>/dev/null
    chmod 777 etc/portage/$d
  done

  for d in package.{accept_keywords,env,mask,unmask,use}
  do
    (cd etc/portage/$d; ln -s ../../../tmp/tb/data/$d.common common)
  done

  touch       etc/portage/package.mask/self     # failed package at this image
  chmod a+rw  etc/portage/package.mask/self

  if [[ "$keyword" = "unstable" ]]; then
    # unmask GCC-6 at 25% of unstable images
    #
    if [[ $(($RANDOM % 4)) -eq 0 ]]; then
      echo "sys-devel/gcc:6.2.0"    > etc/portage/package.unmask/gcc-6
      echo "sys-devel/gcc:6.2.0 **" > etc/portage/package.accept_keywords/gcc-6
    fi
  fi

  touch      etc/portage/package.use/setup     # USE flags added during setup phase
  chmod a+rw etc/portage/package.use/setup

  # support special environments for dedicated packages
  #
  cat << EOF > etc/portage/env/splitdebug
CFLAGS="\$CFLAGS -g -ggdb"
CXXFLAGS="\$CXXFLAGS -g -ggdb"
FEATURES="splitdebug"

EOF

  # no special c++ flags (eg. to revert -Werror=terminate)
  #
  echo 'CXXFLAGS="-O2 -pipe -march=native"' > etc/portage/env/cxx

  # force tests of entries defined in package.env.common
  #
  echo 'FEATURES="test"'                    > etc/portage/env/test

  # we force breakage with XDG_* settings in job.sh
  #
  echo 'FEATURES="-sandbox -usersandbox"'   > etc/portage/env/nosandbox
}


# DNS resolution + .vimrc
#
function CompileMiscFiles()  {
  cp -L /etc/hosts /etc/resolv.conf etc/

  cat << EOF > root/.vimrc
set softtabstop=2
set shiftwidth=2
set tabstop=2
set expandtab

EOF

}


# always upgrade GCC first, then build the kernel, upgrade @system and emerge few mandatory/useful packages
#
function FillPackageList()  {
  pks=tmp/packages

  if [[ -n "$origin" && -e $origin/var/log/emerge.log ]]; then
    # filter out from the randomized package list the ones got from $origin
    #
    qlop --nocolor --list -f $origin/var/log/emerge.log | awk ' { print $7 } ' | xargs qatom | cut -f1-2 -d' ' | tr ' ' '/' > $pks.tmp
    qsearch --all --nocolor --name-only --quiet | sort --random-sort | fgrep -v -f $pks.tmp > $pks
    echo "INFO $(wc -l < $pks.tmp) packages of $origin processed" >> $pks
    tac $pks.tmp >> $pks
    rm $pks.tmp
  else
    qsearch --all --nocolor --name-only --quiet | sort --random-sort > $pks
  fi

  cat << EOF >> $pks
# setup done
app-portage/pfl
app-portage/eix
@system
EOF

  if [[ "$libressl" = "y" ]]; then
    cat << EOF >> $pks
%/tmp/tb/bin/switch2libressl.sh
EOF
  fi

  cat << EOF >> $pks
%emerge -u sys-kernel/hardened-sources
%rm -f /etc/portage/package.mask/setup_blocker
sys-devel/gcc
EOF

  chown tinderbox.tinderbox $pks
}


# create and run a shell script to:
#
# - configure locale, timezone, MTA etc
# - install and configure tools used in job.sh:
#         <package>                   <command/s>
#         app-arch/sharutils          uudecode
#         app-portage/gentoolkit      equery eshowkw revdep-rebuild
#         app-portage/portage-utils   qlop
#         www-client/pybugz           bugz
# - dry test of GCC and @system upgrade to auto-fix package-specific USE flags
#
function EmergeMandatoryPackages() {
  dryrun="emerge --backtrack=30 --deep --update --changed-use --with-bdeps=y @system --pretend"

  cat << EOF > tmp/setup.sh
eselect profile set $profile || exit 6

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "
en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8
" >> /etc/locale.gen
locale-gen || exit 6
eselect locale set en_US.utf8 || exit 6
env-update
source /etc/profile

emerge --noreplace net-misc/netifrc

echo "# packages preventing an upgrade of GCC before @system is made" > /etc/portage/package.mask/setup_blocker

emerge sys-apps/elfix || exit 6
migrate-pax -m

emerge mail-mta/ssmtp || exit 6
emerge mail-client/mailx || exit 6

emerge app-arch/sharutils app-portage/gentoolkit app-portage/portage-utils www-client/pybugz || exit 6

rc=0
emerge --update --pretend sys-devel/gcc || rc=7

mv /etc/portage/package.mask/setup_blocker /tmp

$dryrun &> /tmp/dryrun.log
if [[ \$? -ne 0 ]]; then
  grep -A 1000 'The following USE changes are necessary to proceed:' /tmp/dryrun.log | grep '^>=' | sort -u > /etc/portage/package.use/setup
  if [[ -s /etc/portage/package.use/setup ]]; then
    $dryrun &> /tmp/dryrun.log || rc=7
  else
    rc=7
  fi
fi

mv /tmp/setup_blocker /etc/portage/package.mask/

exit \$rc

EOF

  # <app-admin/eselect-1.4.7 $LANG issue
  #
  (
    cd usr/share/eselect &&\
    wget -q -O- https://598480.bugs.gentoo.org/attachment.cgi?id=451903 2>/dev/null |\
    sed 's,/libs/config.bash.in,/libs/config.bash,g' |\
    patch -p1 --forward
  ) || exit 8

  cd ..
  $(dirname $0)/chr.sh $name '/bin/bash /tmp/setup.sh &> /tmp/setup.log'
  rc=$?

  cd - 1>/dev/null

  # provide credentials only to running images
  #
  (cd root      && ln -snf    ../tmp/tb/sdata/.bugzrc    .)  || exit 8
  (cd etc/ssmtp && ln -snf ../../tmp/tb/sdata/ssmtp.conf .)  || exit 8

  cd $tbhome

  # try to shorten the link to the image, eg.: img1/plasma-..
  #
  d=$(basename $imagedir)/$name
  if [[ ! -d $d ]]; then
    d=$imagedir/$name
  fi

  if [[ $rc -ne 0 ]]; then
    echo
    echo " setup NOT successful (rc=$rc) @ $d"

    if [[ $rc -eq 6 ]]; then
      echo
      cat $d/tmp/setup.log
    elif [[ $rc -eq 7 ]]; then
      echo
      cat $d/tmp/dryrun.log
    fi

    # the usage of "~" is here ok b/c usually those commands are
    # manually run by the user "tinderbox"
    #
    echo
    echo "    view $d/tmp/dryrun.log"
    echo "    vi $d/etc/portage/make.conf"
    echo "    sudo ~/tb/bin/chr.sh $d '  $dryrun  '"
    echo "    (cd ~/run && ln -s ../$d)"
    echo "    ~/tb/bin/start_img.sh $name"
    echo

    exit $rc
  fi

  (cd $tbhome/run && ln -s ../$d) || exit 9

  echo
  echo " setup  OK : $d"
  echo
}


#############################################################################
#
# main
#
if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

# the remote stage3 location
#
imagedir=$(pwd)
wgethost=http://ftp.uni-erlangen.de/pub/mirrors/gentoo
wgetpath=/releases/amd64/autobuilds
latest=latest-stage3.txt

autostart="y"   # start the image after setup ?
flags=$(rufs)   # holds the current USE flag subset
origin=""       # clone from another image ?

# arbitrarily pre-select profile, keyword, ssl vendor and ABI_X86
#
profile=$(eselect profile list | awk ' { print $2 } ' | grep -v -E 'kde|x32|selinux|musl|uclibc|profile|developer' | sort --random-sort | head -n1)

if [[ $(($RANDOM % 20)) -eq 0 ]]; then
  keyword="stable"
else
  keyword="unstable"
fi

if [[ $(($RANDOM % 3)) -eq 0 ]]; then
  libressl="y"
else
  libressl="n"
fi

if [[ "$keyword" = "stable" ]]; then
  libressl="n"
fi

if [[ $(($RANDOM % 3)) -eq 0 ]]; then
  multilib="y"
else
  multilib="n"
fi

echo "$profile" | grep -q 'no-multilib'
if [[ $? -eq 0 ]]; then
  multilib="n"
fi

# the caller can overwrite the (thrown) settings
#
while getopts a:f:k:l:m:o:p: opt
do
  case $opt in
    a)  autostart="$OPTARG"
        ;;

    f)  if [[ -f "$OPTARG" ]] ; then
          # USE flags are either defined as USE="..." or justed listed
          #
          flags="$(source $OPTARG; echo $USE)"
          if [[ -z "$flags" ]]; then
            flags="$(cat $OPTARG)"
          fi
        else
          flags="$OPTARG"
        fi
        ;;

    k)  keyword="$OPTARG"
        if [[ "$keyword" != "stable" && "$keyword" != "unstable" ]]; then
          echo " wrong value for \$keyword: $keyword"
          exit 2
        fi
        ;;

    l)  libressl="$OPTARG"
        if [[ "$libressl" != "y" && "$libressl" != "n" ]]; then
          echo " wrong value for \$libressl: $libressl"
          exit 2
        fi
        ;;

    m)  multilib="$OPTARG"
        if [[ "$multilib" != "y" && "$multilib" != "n" ]]; then
          echo " wrong value for \$multilib $multilib"
          exit 2
        fi
        ;;

    o)  origin="$OPTARG"
        if [[ ! -e $origin ]]; then
          echo "\$origin '$origin' doesn't exist!"
          exit 2
        fi

        profile=$(readlink $origin/etc/portage/make.profile | cut -f6- -d'/')
        flags="$(source $origin/etc/portage/make.conf; echo $USE)"
        grep -q '^CURL_SSL="libressl"' $origin/etc/portage/make.conf
        if [[ $? -eq 0 ]]; then
          libressl="y"
        else
          libressl="n"
        fi
        grep -q '^ACCEPT_KEYWORDS=.*~amd64' $origin/etc/portage/make.conf
        if [[ $? -eq 0 ]]; then
          keyword="unstable"
        else
          keyword="stable"
        fi
        ;;

    p)  profile="$OPTARG"
        if [[ ! -d /usr/portage/profiles/$profile ]]; then
          echo " profile unknown: $profile"
          exit 2
        fi
        ;;

    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 2
        ;;
  esac
done

#############################################################################
#
if [[ "$tbhome" = "$imagedir" ]]; then
  echo "you are in \$tbhome !"
  exit 3
fi

# $latest contains the stage3 file name needed in ComputeImageName()
#
wget --quiet $wgethost/$wgetpath/$latest --output-document=$tbhome/$latest
if [[ $? -ne 0 ]]; then
  echo " wget failed of: $latest"
  exit 3
fi

ComputeImageName
name="${name}_$(date +%Y%m%d-%H%M%S)"
echo " $imagedir/$name"
echo

UnpackStage3
CompilePortageFiles
CompileMiscFiles
FillPackageList
EmergeMandatoryPackages

if [[ "$autostart" = "y" ]]; then
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
fi

exit 0
