#!/bin/bash
# set -x

# replace an older tinderbox image with a newer one


function Finish() {
  local rc=$1
  local pid=$$

  if [[ $rc -ne 0 ]]; then
    echo
    date
    echo " finished $pid with rc=$rc"
  fi

  sed -i -e "/^${pid}$/d" $lck
  if [[ ! -s $lck ]]; then
    rm $lck
  fi

  exit $rc
}


function GetCompletedEmergeOperations() {
  grep -c ' ::: completed emerge' ~/run/$1/var/log/emerge.log 2>/dev/null || echo "0"
}


function NumberOfPackagesInBacklog()  {
  wc -l < ~/run/$1/var/tmp/tb/backlog
}


function LookForAnImageWithEmptyBacklog()  {
  # wanted side effect: $oldimg is set
  while read -r oldimg
  do
    if [[ -e ~/run/$oldimg ]]; then
      if [[ $(wc -l < <(cat ~/run/$oldimg/var/tmp/tb/backlog 2>/dev/null)) = "0" ]]; then
        return 0
      fi
    else
      echo "warn: ~/run/$oldimg is broken !"
    fi
  done < <(cd ~/run; ls -dt * 2>/dev/null | tac)

  return 1
}


function __minDistanceIsReached()  {
  local distance
  (( distance = ($(date +%s) - $(stat -c%Y ~/run/$newest/etc/conf.d/hostname)) / 3600))
  [[ $distance -ge $condition_distance ]] && return 0 || return 1
}


function __ReachedMaxRuntime()  {
  local runtime
  ((runtime = ($(date +%s) - $(stat -c%Y ~/run/$oldimg/etc/conf.d/hostname)) / 3600 / 24))
  [[ $runtime -ge $condition_runtime ]] && return 0 || return 1
}


function __TooLessLeftInBacklog()  {
  [[ $(NumberOfPackagesInBacklog $oldimg) -le $condition_left ]] && return 0 || return 1
}


function __EnoughCompletedEmergeOperations()  {
  [[ $(GetCompletedEmergeOperations $oldimg) -ge $condition_completed ]] && return 0 || return 1
}


function LookForAnImageInRunReadyToBeReplaced()  {
  # hint: $oldimg is set here intentionally as a side effect, but it is used only if "0" is returned
  while read -r oldimg
  do
    if [[ $condition_runtime -gt -1 ]]; then
      if __ReachedMaxRuntime; then
        return 0
      fi
    fi
    if [[ $condition_left -gt -1 ]]; then
      if __TooLessLeftInBacklog; then
        return 0
      fi
    fi
    if [[ $condition_completed -gt -1 ]]; then
      if __EnoughCompletedEmergeOperations; then
        return 0
      fi
    fi
  done < <(cd ~/run; ls -t */etc/conf.d/hostname 2>/dev/null | cut -f1 -d'/' -s | tac)  # from oldest to newest
  return 1
}


function StopOldImage() {
  # repeated STOP to render any external restart-logic for a while
  cat << EOF > ~/run/$oldimg/var/tmp/tb/backlog.1st
STOP
STOP
STOP
STOP
STOP
STOP $(GetCompletedEmergeOperations $oldimg) completed, $(NumberOfPackagesInBacklog $oldimg) left
EOF

  # do not wait for an empty backlog.1st b/c job.sh might inject @preserved-rebuilds et al into it
  ${0%/*}/stop_img.sh $oldimg

  local lock_dir=/run/tinderbox/$oldimg.lock
  if [[ -d $lock_dir ]]; then
    date
    echo " waiting for image unlock ..."
    while [[ -d $lock_dir ]]
    do
      sleep 1
    done
    date
    echo " image is unlocked"
  else
    echo " image was not locked"
  fi
}


#######################################################################
set -eu
export LANG=C.utf8

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

condition_completed=-1      # completed emerge operations
condition_distance=-1       # distance in hours to the previous image
condition_left=-1           # left entries in backlogs
condition_runtime=-1     # age in days for an image

oldimg=""                   # optional: image name to be replaced ("-" to add a new one), no paths allowed!
setupargs=""                # argument(s) for setup_img.sh

while getopts c:d:l:o:r:s: opt
do
  case "$opt" in
    c)  condition_completed="$OPTARG"   ;;
    d)  condition_distance="$OPTARG"    ;;
    l)  condition_left="$OPTARG"        ;;
    r)  condition_runtime="$OPTARG"     ;;

    o)  oldimg="${OPTARG##*/}"          ;;
    s)  setupargs="$OPTARG"             ;;
    *)  echo " opt not implemented: '$opt'"; exit 1;;
  esac
done

# do not run this script in parallel
lck="/tmp/${0##*/}.lck"
if [[ -s "$lck" ]]; then
  if kill -0 $(cat $lck) 2>/dev/null; then
    exit 1    # process is running
  fi
fi
echo $$ >> "$lck" || Finish 1

if [[ -z "$oldimg" ]]; then
  if ! LookForAnImageWithEmptyBacklog; then
    newest=$(cd ~/run; ls -t */etc/conf.d/hostname 2>/dev/null | cut -f1 -d'/' -s | head -n 1)
    if [[ -z "$newest" ]]; then
      Finish 0
    fi
    if [[ $condition_distance -gt -1 ]]; then
      if ! __minDistanceIsReached; then
        Finish 0
      fi
    fi
    if ! LookForAnImageInRunReadyToBeReplaced; then
      Finish 0
    fi
  fi
elif [[ ! $oldimg = "-" && ! -e ~/run/$oldimg ]]; then
  echo " error, old image not found: $oldimg"
  Finish 1
fi

if [[ -e ~/run/$oldimg ]]; then
  echo
  date
  echo " replacing $oldimg ..."
  StopOldImage
fi

echo
date
echo " setup a new image ..."

if sudo ${0%/*}/setup_img.sh $setupargs; then
  if [[ -e ~/run/$oldimg ]]; then
    rm -- ~/run/$oldimg ~/logs/$oldimg.log
  fi
  Finish 0
else
  Finish $?
fi

