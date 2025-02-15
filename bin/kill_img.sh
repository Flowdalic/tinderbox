#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# set an image EOL, kill a running emerge process -or- the entrypoint script itself


#######################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

for img in ${*?got no image}
do
  img=$(basename "$img")
  if [[ -d ~tinderbox/img/$img ]]; then
    echo "user decision at $(date)" >> ~tinderbox/img/$img/var/tmp/tb/EOL
    chmod g+w ~tinderbox/img/$img/var/tmp/tb/EOL
    chgrp tinderbox ~tinderbox/img/$img/var/tmp/tb/EOL
    if pid_bwrap=$(pgrep -f "sudo.*bwrap.*$img"); then
      if [[ -n $pid_bwrap ]]; then
        if pid_emerge=$(pstree -pa $pid_bwrap | grep -F 'emerge,' | grep -m1 -Eo ',([[:digit:]]+) ' | tr -d ','); then
          if [[ -n $pid_emerge ]]; then
            pstree -UlnspuTa $pid_emerge | head -n 500
            echo
            kill -9 $pid_emerge
          else
            echo " warning: empty emerge pid from $pid_bwrap"
            if pid_entrypoint=$(pstree -pa $pid_bwrap | grep -F 'entrypoint,' | grep -m1 -Eo ',([[:digit:]]+) ' | tr -d ','); then
              if [[ -n $pid_entrypoint ]]; then
                pstree -UlnspuTa $pid_entrypoint | head -n 500
                echo
                kill -15 $pid_entrypoint
                sleep 60
                echo
                kill -0 $pid_entrypoint && kill -9 $pid_entrypoint
                echo
              else
                echo " error: empty entrypoint pid from $pid_bwrap"
              fi
            else
              echo " error: could not get entrypoint pid from $pid_bwrap"
            fi
          fi
        else
          echo " error: could not get emerge pid from $pid_bwrap"
        fi
      else
        echo " error: empty bwrap pid"
      fi
    else
      echo " error: could not get bwrap pid"
    fi
  else
    echo " error: $img: image not found"
  fi
done
