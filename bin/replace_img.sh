#!/bin/bash
# set -x

# setup a new image or replace an older one


function Finish() {
  local rc=${1:-$?}
  local pid=$$

  trap - INT QUIT TERM EXIT

  if [[ $rc -ne 0 ]]; then
    echo
    date
    echo " pid $pid exited with rc=$rc"
  fi
  rm $lck

  exit $rc
}


function GetCompletedEmergeOperations() {
  grep -c ' ::: completed emerge' ~/run/$oldimg/var/log/emerge.log 2>/dev/null || echo "0"
}


function NumberOfPackagesInBacklog()  {
  wc -l 2>/dev/null < ~/run/$oldimg/var/tmp/tb/backlog || echo "0"
}


function AnImageHasAnEmptyBacklog()  {
  # set $oldimg here intentionally
  while read -r oldimg
  do
    if [[ -e ~/run/$oldimg ]]; then
      local bl=~/run/$oldimg/var/tmp/tb/backlog
      if [[ -f $bl ]]; then
        if [[ $(wc -l < $bl) -eq 0 ]]; then
          return 0
        fi
      else
        echo "warn: $bl is missing !"
      fi
    else
      echo "warn: ~/run/$oldimg is broken !"
    fi
  done < <(cd ~/run; ls -dt * 2>/dev/null | tac)

  return 1
}


function MinDistanceIsReached()  {
  local newest=$(cd ~/run; ls -t */etc/conf.d/hostname 2>/dev/null | cut -f1 -d'/' -s | head -n 1)
  if [[ -z "$newest" ]]; then
    return 1
  fi

  local distance
  (( distance = ($(date +%s) - $(stat -c%Y ~/run/$newest/etc/conf.d/hostname)) / 3600))
  [[ $distance -ge $condition_distance ]]
}


function MaxCountIsRunning()  {
  if ! pgrep -f $(dirname $0)/setup_img.sh 1>/dev/null; then
    [[ $(ls ~/run/ 2>/dev/null | wc -l) -ge $condition_count || $(ls /run/tinderbox 2>/dev/null | wc -l) -ge $condition_count ]]
  fi
}


function __ReachedMaxRuntime()  {
  local runtime
  ((runtime = ($(date +%s) - $(stat -c%Y ~/run/$oldimg/etc/conf.d/hostname)) / 3600 / 24))
  [[ $runtime -ge $condition_runtime ]]
}


function __TooSmallBacklog()  {
  [[ $(NumberOfPackagesInBacklog) -le $condition_left ]]
}


function __EnoughCompletedEmergeOperations()  {
  [[ $(GetCompletedEmergeOperations) -ge $condition_completed ]]
}


function AnImageReachedEOL()  {
  # hint: $oldimg is set here intentionally as a side effect, but it is used only if "0" is returned
  while read -r oldimg
  do
    if [[ $condition_runtime -gt -1 ]]; then
      if __ReachedMaxRuntime; then
        reason="reached max runtime"
        return 0
      fi
    fi
    if [[ $condition_left -gt -1 ]]; then
      if __TooSmallBacklog; then
        reason="too small backlog"
        return 0
      fi
    fi
    if [[ $condition_completed -gt -1 ]]; then
      if __EnoughCompletedEmergeOperations; then
        reason="enough completed"
        return 0
      fi
    fi
  done < <(cd ~/run; ls -t */etc/conf.d/hostname 2>/dev/null | cut -f1 -d'/' -s | tac)  # from oldest to newest
  return 1
}


function StopOldImage() {
  local msg="replace reason: $1"

  echo
  date
  echo " stopping $oldimg, $msg"

  if [[ -z $oldimg || ~/run/$oldimg = "-" || ! -e ~/run/$oldimg ]]; then
    echo "invalid file name"
    exit 1
  fi

  # repeat STOP to stop again immediately after an external triggered restart
  cat << EOF > ~/run/$oldimg/var/tmp/tb/backlog.1st
STOP
STOP
STOP
STOP
STOP
STOP $msg
EOF

  # do not put a "STOP" into backlog.1st b/c job.sh might inject @preserved-rebuilds et al before it
  ${0%/*}/stop_img.sh $oldimg

  local lock_dir=/run/tinderbox/$oldimg.lock
  if [[ -d $lock_dir ]]; then
    date
    echo " waiting for image unlock ..."
    while [[ -d $lock_dir ]]
    do
      sleep 1
    done
  fi
  rm -- ~/run/$oldimg ~/logs/$oldimg.log
  echo "done"
}


function setupANewImage() {
  echo
  date
  echo " setup a new image ..."
  nice -n 1 sudo ${0%/*}/setup_img.sh $setupargs
}


#######################################################################
set -eu
export LANG=C.utf8

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

# do not run this script in parallel
lck="/tmp/${0##*/}.lck"
if [[ -s "$lck" ]]; then
  if kill -0 $(cat $lck) 2>/dev/null; then
    exit 1    # process is running
  fi
fi
echo $$ > "$lck" || exit 1
trap Finish INT QUIT TERM EXIT

condition_completed=-1      # completed emerge operations
condition_distance=-1       # distance in hours to the previous image
condition_left=-1           # left entries in backlogs
condition_runtime=-1        # age in days for an image
condition_count=-1          # number of images to be run

oldimg=""                   # optional: image name to be replaced ("-" to add a new one), no paths allowed!
setupargs=""                # argument(s) for setup_img.sh

while getopts c:d:l:n:o:r:s: opt
do
  case "$opt" in
    c)  condition_completed="$OPTARG"   ;;
    d)  condition_distance="$OPTARG"    ;;
    l)  condition_left="$OPTARG"        ;;
    n)  condition_count="$OPTARG"       ;;
    r)  condition_runtime="$OPTARG"     ;;

    o)  oldimg="${OPTARG##*/}"          ;;
    s)  setupargs="$OPTARG"             ;;
    *)  echo " opt not implemented: '$opt'"; exit 1;;
  esac
done

if [[ -z "$oldimg" ]]; then
  if [[ $condition_count -gt -1 ]]; then
    while ! MaxCountIsRunning
    do
      setupANewImage
    done
  fi

  while AnImageHasAnEmptyBacklog
  do
    StopOldImage "empty backlogs"
    setupANewImage
  done

  if [[ $condition_runtime -gt -1 || $condition_left -gt -1 || $condition_completed -gt -1 ]]; then
    while AnImageReachedEOL
    do
      StopOldImage "$reason"
      if [[ $condition_distance -eq -1 ]] || MinDistanceIsReached; then
        setupANewImage
      else
        break
      fi
    done
  fi

else
  if [[ ! $oldimg = "-" ]]; then
    StopOldImage "user decision"
  fi
  setupANewImage
fi

Finish $?
