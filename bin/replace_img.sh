#!/bin/bash
# set -x

# replace an image with a new one


function Finish() {
  local rc=${1:-$?}
  local pid=$$

  trap - INT QUIT TERM EXIT

  if [[ $rc -ne 0 ]]; then
    echo
    date
    echo " pid $pid exited with rc=$rc"
  fi

  rm $lockfile
  exit $rc
}


function ImagesInRunShuffled() {
  (set +f; cd ~tinderbox/run; ls -d * 2>/dev/null | shuf)
}


function FreeSlotAvailable() {
  r=$(ls /run/tinderbox 2>/dev/null | wc -l)
  s=$(pgrep -c -f $(dirname $0)/setup_img.sh)

  [[ $(( r+s )) -lt $desired_count && $(ImagesInRunShuffled | wc -l) -lt $desired_count ]]
}


function setupNewImage() {
  echo
  date
  echo " setup a new image ..."
  sudo $(dirname $0)/setup_img.sh
}


#######################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

source $(dirname $0)/lib.sh

desired_count=14            # number of images to be run
while getopts n:u: opt
do
  case "$opt" in
    n)  desired_count="$OPTARG" ;;
    u)  echo "user decision" >> ~tinderbox/img/$(basename $OPTARG)/var/tmp/tb/REPLACE_ME;;
    *)  echo "unknown parameter '${opt}'"; exit 1;;
  esac
done

# do not run in parallel from here
lockfile="/tmp/$(basename $0).lck"
if [[ -s "$lockfile" ]]; then
  if kill -0 $(cat $lockfile) 2>/dev/null; then
    exit 1    # a previous instance is (still) running
  else
    echo " found stale lockfile content:"
    cat $lockfile
  fi
fi
echo $$ > "$lockfile" || exit 1
trap Finish INT QUIT TERM EXIT

while :
do
  # mark a stopped image after 1.5 days as to be replaced
  while read -r oldimg
  do
    if ! __is_running $oldimg; then
      hours=$(( (EPOCHSECONDS-$(stat -c %Y ~tinderbox/img/$oldimg/var/tmp/tb/task))/3600 ))
      if [[ $hours -ge 36 ]]; then
        echo -e "last task $hours hour/s ago" >> ~tinderbox/img/$oldimg/var/tmp/tb/REPLACE_ME
      fi
    fi
  done < <(ImagesInRunShuffled)

  # free the slot
  while read -r oldimg
  do
    if ! __is_running $oldimg; then
      if [[ -f ~tinderbox/run/$oldimg/var/tmp/tb/REPLACE_ME ]]; then
        rm ~tinderbox/run/$oldimg ~tinderbox/logs/$oldimg.log
      fi
    fi
  done < <(ImagesInRunShuffled)

  if FreeSlotAvailable; then
    if setupNewImage; then
      continue
    else
      echo
      date
      echo " setup failed"
      Finish 1
    fi
  fi

  # are there still running images marked as to be replaced ?
  while read -r oldimg
  do
    if __is_running $oldimg; then
      if [[ -f ~tinderbox/run/$oldimg/var/tmp/tb/REPLACE_ME ]]; then
        sleep 10
        continue 2
      fi
    fi
  done < <(ImagesInRunShuffled)

  break
done

Finish 0
