#!/bin/sh
#
# set -x

# setup a new tinderbox image
#
# typical call:
#
# echo "cd ~/img2; sudo /opt/tb/bin/tbs.sh -p 17.0/desktop/gnome -l y -m n" | at now + 0 min

#############################################################################
#
# functions
#

# create a (r)andomized (U)SE (f)lag (s)ubset
#
function rufs()  {
  n=99   # choose between 0 and n-1 USE flags
  m=5    # about 1/m will be masked

  (
    grep -v -e '^$' -e '^#' -e 'internal use only' -e 'DO NOT USE THIS' /usr/portage/profiles/use.desc
    grep -v -e '^$' -e '^#' -e 'internal use only' -e 'DO NOT USE THIS' /usr/portage/profiles/use.local.desc | cut -f2 -d ':' -s
  ) |\
  cut -f1 -d ' ' |\
  grep -v   -e '32' -e '64' -e 'bindist' -e 'build' -e 'cdinstall' \
            -e 'gcj' -e 'hostname' -e 'linguas' -e 'make-symlinks' -e 'multilib' -e 'musl'  \
            -e 'oci8' -e 'pax' -e 'qt4' -e 'tools' -e 'selinux' -e 'ssl' -e 'ssp' -e 'static' -e 'systemd'    \
            -e 'test' -e 'tls' -e 'uclibc' -e 'vim-syntax' |\
  sort -u -R |\
  head -n $(($RANDOM % $n)) |\
  sort |\
  while read flag
  do
    if [[ $(($RANDOM % $m)) -eq 0 ]]; then
      echo -n "-"
    fi
    echo -n "$flag "
  done
}


# deduce the tinderbox image name from profile and stage3 filename
#
function ComputeImageName()  {
  b="$(basename $profile)"
  case $b in
    no-multilib)  stage3=$(grep "^20....../stage3-amd64-nomultilib-20.......tar.bz2" $latest | cut -f1 -d' ' -s)
    ;;
    systemd)      stage3=$(grep "^20....../$b/stage3-amd64-$b-20.......tar.bz2" $latest | cut -f1 -d' ' -s)
    ;;
    *)            stage3=$(grep "^20....../stage3-amd64-20.......tar.bz2" $latest | cut -f1 -d' ' -s)
    ;;
  esac

  if [[ -z "$stage3" ]]; then
    echo "can't get stage 3 from profile '$profile'"
    exit 3
  fi

  name="$(echo $profile | tr '/' '-')"

  # the 1st underscore splits the profile
  #
  name="${name}_"

  if [[ "$keyword" = "stable" ]]; then
    name="$name-stable"
  fi

  if [[ "$libressl" = "y" ]]; then
    name="$name-libressl"
  fi

  if [[ "$multilib" = "y" ]]; then
    name="$name-abi32+64"
  fi

  if [[ -n "$suffix" ]]; then
    name="$name-$suffix"
  fi

  # the 2nd underscore splits the date
  #
  name="${name}_$(date +%Y%m%d-%H%M%S)"

  name="$(echo $name | sed -e 's/_[-_]/_/g')"
}


# download, verify and unpack the stage3 file
#
function UnpackStage3()  {
  f=$distfiles/$(basename $stage3)
  if [[ ! -s $f ]]; then
    wget --quiet --no-clobber $wgethost/$wgetpath/$stage3{,.DIGESTS.asc} --directory-prefix=$distfiles || exit 4
  fi

  # do this once before:
  #
  # gpg --keyserver hkps.pool.sks-keyservers.net --recv-keys 0x9E6438C817072058
  # gpg --edit-key 0x9E6438C817072058
  #   and "trust" it (5==ultimately)
  # maybe: do the same for 0xBB572E0E2D182910
  #
  gpg --quiet --verify $f.DIGESTS.asc || exit 4
  echo

  mkdir $name || exit 4
  cd $name    || exit 4
  tar -xjpf $f --xattrs --exclude='./dev/*' || exit 4
}


# configure our 3 repositories and prepare 1 placeholder too
# the local repository rules always
#
function CompileRepoFiles()  {
  mkdir -p     ./etc/portage/repos.conf/
  cat << EOF > ./etc/portage/repos.conf/default.conf
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

  cat << EOF > ./etc/portage/repos.conf/gentoo.conf
[gentoo]
location  = /usr/portage
auto-sync = no
EOF

  cat << EOF > ./etc/portage/repos.conf/tinderbox.conf
[tinderbox]
location  = /tmp/tb/data/portage
masters   = gentoo
auto-sync = no
EOF

  cat << EOF > ./etc/portage/repos.conf/foo.conf
#[foo]
#location  = /usr/local/foo
#auto-sync = yes
#sync-type = git
#sync-uri  = https://anongit.gentoo.org/git/proj/foo.git
EOF

  cat << EOF > ./etc/portage/repos.conf/local.conf
[local]
location  = /usr/local/portage
masters   = gentoo
auto-sync = no
EOF
}


# compile make.conf
#
function CompileMakeConf()  {
  sed -i  -e '/^CFLAGS="/d'       \
          -e '/^CXXFLAGS=/d'      \
          -e '/^CPU_FLAGS_X86=/d' \
          -e '/^USE=/d'           \
          -e '/^PORTDIR=/d'       \
          -e '/^PKGDIR=/d'        \
          -e '/^#/d'              \
          -e '/^DISTDIR=/d'       \
          ./etc/portage/make.conf

  # put tinderbox before into group "portage"
  #
  chgrp portage ./etc/portage/make.conf
  chmod g+w ./etc/portage/make.conf

  if [[ -e $origin/etc/portage/make.conf ]]; then
    l10n=$(grep "^L10N=" $origin/etc/portage/make.conf | cut -f2- -d'=' -s)
  else
    l10n="$(grep -v -e '^$' -e '^#' /usr/portage/profiles/desc/l10n.desc | cut -f1 -d' ' | sort --random-sort | head -n $(($RANDOM % 10)) | sort | xargs)"
  fi

  cat << EOF >> ./etc/portage/make.conf
CFLAGS="-O2 -pipe -march=native -Wall"
CXXFLAGS="-O2 -pipe -march=native"

USE="
$( echo $flags | xargs -s 78 | sed 's/^/  /g' )

  ssp -bindist -cdinstall -oci8
"
PAX_MARKINGS="none"

ACCEPT_KEYWORDS=$( [[ "$keyword" = "unstable" ]] && echo '~amd64' || echo 'amd64' )

ACCEPT_LICENSE="*"

MAKEOPTS="-j1"
NINJAFLAGS="-j1"

EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --color=n --nospinner --tree --quiet-build"
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"
CLEAN_DELAY=0

ALSA_CARDS="hda-intel"
INPUT_DEVICES="evdev libinput"
VIDEO_CARDS="intel i965"

L10N="$l10n"

FEATURES="xattr preserve-libs parallel-fetch ipc-sandbox network-sandbox -news"

DISTDIR="$distfiles"
PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

PORTAGE_GPG_DIR="/var/lib/gentoo/gkeys/keyrings/gentoo/release"

GENTOO_MIRRORS="$wgethost rsync://mirror.netcologne.de/gentoo/ ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/gor.bytemark.co.uk/gentoo/ rsync://ftp.snt.utwente.nl/gentoo"
EOF
}


# symlink within an image a bunch of (host bind mounted) files
# from /tmp/tb/data to the appropriate portage directories
#
function CompilePackageFiles()  {
  mkdir tmp/tb  # mount point for the tinderbox directory of the host

  # create portage directories and symlinks
  #
  mkdir ./usr/portage
  mkdir ./var/tmp/{distfiles,portage}

  for d in package.{accept_keywords,env,mask,unmask,use} env profile
  do
    [[ ! -d ./etc/portage/$d ]] && mkdir ./etc/portage/$d
    chmod 777 ./etc/portage/$d
  done

  (cd ./etc/portage; ln -s ../../tmp/tb/data/patches)

  for d in package.{accept_keywords,env,mask,unmask,use}
  do
    (cd ./etc/portage/$d && ln -s ../../../tmp/tb/data/$d.common common)
  done

  for d in package.{accept_keywords,unmask}
  do
    (cd ./etc/portage/$d && ln -s ../../../tmp/tb/data/$d.$keyword $keyword)
  done

  touch       ./etc/portage/package.mask/self     # contains failed package at this image
  chmod a+rw  ./etc/portage/package.mask/self

  touch      ./etc/portage/package.use/setup      # USE flags added during setup phase
  chmod a+rw ./etc/portage/package.use/setup

  # activate at every n-th image predefined USE flag sets
  #
  if [[ $(($RANDOM % 100)) -lt 40 ]]; then
    (cd ./etc/portage/package.use && ln -s ../../../tmp/tb/data/package.use.ff-and-tb ff-and-tb)
  fi

  if [[ $(($RANDOM % 100)) -lt 25 ]]; then
    (cd ./etc/portage/package.use && ln -s ../../../tmp/tb/data/package.use.ffmpeg ffmpeg)
  fi

  echo "*/* $(cpuid2cpuflags)" > ./etc/portage/package.use/00cpuflags

  if [[ "$(basename $profile)" = "systemd" ]]; then
    echo "sys-apps/util-linux -udev" >> ./etc/portage/package.use/util-linux
  fi

  # create package specific env files
  #
  cat << EOF > ./etc/portage/env/splitdebug
CFLAGS="\$CFLAGS -g -ggdb"
CXXFLAGS="\$CXXFLAGS -g -ggdb"
FEATURES="splitdebug"
EOF

  # no special c++ flags (eg. to revert "-Werror=terminate" which will be set in job.sh for gcc-6)
  #
  echo 'CXXFLAGS="-O2 -pipe -march=native"' > ./etc/portage/env/cxx

  # force tests for packages defined in package.env.common
  #
  echo 'FEATURES="test"'                    > ./etc/portage/env/test

  # deny tests for packages defined in package.env.common
  #
  echo 'FEATURES="-test"'                   > ./etc/portage/env/notest

  # breakage is forced in job.sh by the XDG_* variables
  #
  echo 'FEATURES="-sandbox -usersandbox"'   > ./etc/portage/env/nosandbox

  # test known to be broken
  #
  echo 'FEATURES="test-fail-continue"'      > ./etc/portage/env/test-fail-continue
}


# configure DNS
# configure vim (eg.: avoid interactive question)
#
function CompileMiscFiles()  {
  # "mr-fox" must be resolved to "127.0.0.1" or "::1" respectively
  #
  cat <<EOF > ./etc/resolv.conf
domain localdomain
nameserver 127.0.0.1
EOF

  cat <<EOF > ./etc/hosts
127.0.0.1 localhost $(hostname) $(hostname -f)
::1       localhost $(hostname) $(hostname -f)
EOF

  cat << EOF > ./root/.vimrc
set softtabstop=2
set shiftwidth=2
set expandtab
let g:session_autosave = 'no'
autocmd BufEnter *.txt set textwidth=0
EOF
}


# the last line of the package list will be the first task and so on
#
function FillPackageList()  {
  pks=./tmp/packages

  # in favour of a good coverage do not test repo changes at all images
  #
  if [[ $(($RANDOM % 3)) -eq 0 ]]; then
    echo '# this keeps insert_pkgs.sh away' > $pks
  fi

  # fill up the randomized package list
  #
  qsearch --all --nocolor --name-only --quiet | sort --random-sort >> $pks

  # replay tasks, not emerge history
  # skip @sets, b/c @system and @world are scheduled in the new image at different timestamps
  #
  #
  if [[ -e $origin/tmp/task.history ]]; then
    echo "INFO task history of $origin replayed" >> $pks
    n=$(tac $origin/tmp/task.history | grep -v -E "^(%|@|#)" | tee -a $pks | wc -l)
    echo "INFO replay $n tasks of $origin" >> $pks
  fi

  # emerge/upgrade mandatory package/s and update the image
  # use "%..." to bail out in case of an error
  # "# ..." keeps insert_pks.sh away till the basic image setup is done
  #
  cat << EOF >> $pks
# setup done
%emerge -u sys-kernel/gentoo-sources
@world
app-text/wgetpaste
app-portage/pfl
app-portage/eix
@system
%rm -f /etc/portage/package.mask/setup_blocker
EOF

  # switch to the other SSL vendor before @system
  #
  if [[ "$libressl" = "y" ]]; then
    cp $(dirname $0)/switch2libressl.sh ./tmp/
    echo "%/tmp/switch2libressl.sh" >> $pks
  fi

  #
  cat << EOF >> $pks
%emerge -u sys-devel/gcc
sys-apps/sandbox
EOF

  chmod a+w $pks
}


# repos.d/* , make.conf and all the stuff
#
function ConfigureImage()  {
  mkdir -p                  ./usr/local/portage/{metadata,profiles}
  echo 'masters = gentoo' > ./usr/local/portage/metadata/layout.conf
  echo 'local' >            ./usr/local/portage/profiles/repo_name
  chown -R portage:portage  ./usr/local/portage/
  chmod g+s                 ./usr/local/portage/

  CompileRepoFiles
  CompileMakeConf
  CompilePackageFiles
  CompileMiscFiles
  FillPackageList
}


# create a shell script to:
#
# - configure locale, timezone, MTA etc
# - install and configure tools used in job.sh:
#         <package>                   <command/s>
#         app-arch/sharutils          uudecode
#         app-portage/gentoolkit      equery eshowkw revdep-rebuild
#         app-portage/portage-utils   qlop
#         www-client/pybugz           bugz
# - try to auto-fix package-specific USE flags deps of @system upgrade
#
function CreateSetupScript()  {
  dryrun="emerge --backtrack=200 --deep --update --changed-use @system --pretend"
  perl_stable_version=$(portageq best_version / dev-lang/perl)

  cat << EOF > tmp/setup.sh
#!/bin/sh
#
#set -x

cd /etc/portage
ln -snf ../../usr/portage/profiles/default/linux/amd64/$profile make.profile || exit 6
[[ ! -e make.profile ]] && exit 6

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "
en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8
" >> /etc/locale.gen
locale-gen -j1 || exit 6
eselect locale set en_US.utf8 || exit 6
env-update
source /etc/profile

emerge --noreplace net-misc/netifrc

# unstable Perl versions often prevents basic setup, GCC upgrade or LibreSSL switch
#
echo ">${perl_stable_version}" > /etc/portage/package.mask/setup_blocker

emerge mail-mta/ssmtp || exit 7
emerge mail-client/mailx || exit 7
(cd /etc/ssmtp && ln -snf ../../tmp/tb/sdata/ssmtp.conf) || exit 7

emerge app-arch/sharutils app-portage/gentoolkit app-portage/portage-utils www-client/pybugz || exit 8
(cd /root && ln -snf ../tmp/tb/sdata/.bugzrc) || exit 8

\$( [[ "$multilib" = "y" ]] && echo 'ABI_X86="32 64"' >> /etc/portage/make.conf )

mv /etc/portage/package.mask/setup_blocker /tmp/

rc=9
for i in 1 2 3 4 5
do
  $dryrun &> /tmp/dryrun.log
  if [[ \$? -eq 0 ]]; then
    rc=0
    break
  fi

  if [[ \$i -eq 5 ]]; then
    break
  fi

  echo "#round \$i" >> /etc/portage/package.use/setup
  grep -A 1000 'The following USE changes are necessary to proceed:' /tmp/dryrun.log | grep '^>=' | sort -u >> /etc/portage/package.use/setup
  grep -A 1 'by applying the following change:' /tmp/dryrun.log | grep '^-' | cut -f2,5 -d' ' -s | sed -e 's/^/>=/' -e 's/)//' >> /etc/portage/package.use/setup

  tail -n 1 /etc/portage/package.use/setup | grep -q '#round'
  if [[ \$? -eq 0 ]]; then
    break
  fi
done

mv /tmp/setup_blocker /etc/portage/package.mask/

exit \$rc
EOF
}


# at least a MTA and bugz are needed
#
function EmergeMandatoryPackages() {
  CreateSetupScript

  cd /home/tinderbox/

  $(dirname $0)/chr.sh $mnt '/bin/bash /tmp/setup.sh &> /tmp/setup.log'
  rc=$?

  if [[ $rc -ne 0 ]]; then
    echo
    echo " setup NOT successful (rc=$rc) @ $mnt"
    echo

    if [[ $rc -eq 9 ]]; then
      cat $mnt/tmp/dryrun.log
    else
      cat $mnt/tmp/setup.log
    fi

    echo
    echo "    view ~/$mnt/tmp/dryrun.log"
    echo "    vi ~/$mnt/etc/portage/make.conf"
    echo "    sudo $(dirname $0)/chr.sh $mnt '  $dryrun  '"
    echo "    (cd ~/run && ln -s ../$mnt)"
    echo "    start_img.sh $name"
    echo

    exit $rc
  fi
}


#############################################################################
#
# main
#
if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

# store the stage3 images in the distfiles directory
#
distfiles=/var/tmp/distfiles

# the remote stage3 location
#
wgethost=http://ftp.uni-erlangen.de/pub/mirrors/gentoo
wgetpath=/releases/amd64/autobuilds

autostart="y"   # start the image after setup ?
origin=""       # clone from another image ?
suffix=""       # will be appended onto the name before the timestamp

# choose an arbitrary profile
#
profile=$(eselect profile list | awk ' { print $2 } ' | grep -e "^default/linux/amd64" | cut -f4- -d'/' -s | grep -v -e '/x32' -e '/developer' -e '/selinux' | sort --random-sort | head -n 1)

# switch to 17.0 profile at every n-th image
#
if [[ $(($RANDOM % 3)) -eq 0 ]]; then
  profile="$(echo $profile | sed -e 's/13/17/')"
fi

# to test stable use the command line option
#
keyword="unstable"

if [[ $(($RANDOM % 3)) -eq 0 ]]; then
  libressl="y"
else
  libressl="n"
fi

# LibreSSL isn't ready for stable
#
if [[ "$keyword" = "stable" ]]; then
  libressl="n"
fi

# legacy: 32 bit libs
#
multilib="n"

# create a randomized USE flag subset
#
flags=$(rufs)

while getopts a:f:k:l:m:o:p:s: opt
do
  case $opt in
    a)  autostart="$OPTARG"
        ;;

    f)  if [[ -f "$OPTARG" ]] ; then
          # USE flags are either defined after USE="..." or justed listed as-is
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
          echo "\$origin '$origin' doesn't exist"
          exit 2
        fi

        profile=$(cd $origin && realpath ./etc/portage/make.profile | sed 's,.*/profiles/,,')
        flags="$(source $origin/etc/portage/make.conf && echo $USE)"

        grep -q '^CURL_SSL="libressl"' $origin/etc/portage/make.conf
        if [[ $? -eq 0 ]]; then
          libressl="y"
          flags="$(echo $flags | xargs -n 1 | grep -v -e 'openssl' -e 'libressl' -e 'gnutls' | xargs)"
        else
          libressl="n"
        fi

        grep -q '^ACCEPT_KEYWORDS=.*~amd64' $origin/etc/portage/make.conf
        if [[ $? -eq 0 ]]; then
          keyword="unstable"
        else
          keyword="stable"
        fi

        grep -q '#ABI_X86="32 64"' $origin/etc/portage/make.conf
        if [[ $? -eq 0 ]]; then
          multilib="y"
        else
          multilib="n"
        fi
        ;;

    p)  profile="$OPTARG"
        if [[ ! -d /usr/portage/profiles/default/linux/amd64/$profile ]]; then
          echo " profile unknown: $profile"
          exit 2
        fi
        ;;

    s)  suffix="$OPTARG"
        ;;

    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 2
        ;;
  esac
done

#############################################################################
#
if [[ "$(pwd)" = "/home/tinderbox" ]]; then
  echo "you are in /home/tinderbox !"
  exit 3
fi

latest=$distfiles/latest-stage3.txt
wget --quiet $wgethost/$wgetpath/latest-stage3.txt --output-document=$latest || exit 3

ComputeImageName
mnt=$(pwd | sed 's,/home/tinderbox/,,g')/$name
echo " $mnt"
echo
UnpackStage3
ConfigureImage
EmergeMandatoryPackages

cd /home/tinderbox/run && ln -s ../$mnt || exit 11
echo " setup  OK: $name"

if [[ "$autostart" = "y" ]]; then
  echo
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
fi

exit 0
