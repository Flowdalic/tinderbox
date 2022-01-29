function __is_running() {
  local b=$(basename $1)

  [[ -d /sys/fs/cgroup/cpu/local/$b/ ]] || __is_locked $1
}


function __is_locked() {
  local b=$(basename $1)

  [[ -d /run/tinderbox/$b.lock/ ]]
}


function __getStartTime() {
  local b=$(basename $1)

  cat ~tinderbox/img/$b/var/tmp/tb/setup.timestamp
}

