#!/bin/bash
# set -x

# print tinderbox statistics


function PrintImageName()  {
  # ${n} is the minimum length to distinguish image names
  local n=${2}
  printf "%-${n}s" $(cut -c-$n <<< $(basename $1))
}


function check_history()  {
  local file=$1
  local flag=$2

  # eg.:
  # X = @x failed even to start
  # x = @x failed due to a package
  # . = never run before
  #   = no issues
  if [[ -s $file ]]; then
    local line=$(tail -n 1 $file)

    if grep -q " NOT ok " <<< $line; then
      if grep -q " NOT ok $" <<< $line; then
        local uflag=$(tr '[:lower:]' '[:upper:]' <<< $flag)
        flags="${uflag}${flags}"
      else
        flags="${flag}${flags}"
      fi
    elif grep -q " ok$" <<< $line; then
      flags=" $flags"
    else
      flags="?$flags"
    fi
  else
    flags=".$flags"
  fi
}


# whatsup.sh -o
#
# compl fail new day backlog .upd .1st swprs 7#7 running
#  4402   36   1 4.8   16529    7    0  W r  ~/run/17.1-20210306-163653
#  4042   26   0 5.1   17774   12    2    r  ~/run/17.1_desktop_gnome-20210306-091529
function Overall() {
  local running=$(ls /run/tinderbox/ 2>/dev/null | grep -c '\.lock$' || true)
  local all=$(wc -w <<< $images)
  echo "compl fail new  day backlog .upd .1st swprs $running#$all running"

  for i in $images
  do
    local days=$(echo "scale=1; ( $(date +%s) - $(getStartTime $i) ) / 86400.0" | bc)
    local bgo=$(set +f; ls $i/var/tmp/tb/issues/*/.reported 2>/dev/null | wc -l)

    local compl=0
    f=$i/var/log/emerge.log
    if [[ -f $f ]]; then
      compl=$(grep -c ' ::: completed emerge' $f) || true
    fi

    # count emerge failures based on distinct package name+version+release
    # example of an issue directory name: 20200313-044024-net-analyzer_iptraf-ng-1.1.4-r3
    local fail=0
    if [[ -d $i/var/tmp/tb/issues ]]; then
      fail=$(ls -1 $i/var/tmp/tb/issues | while read -r i; do echo $(basename $i); done | cut -f3- -d'-' -s | sort -u | wc -w)
    fi

    local bl=$( wc -l 2>/dev/null < $i/var/tmp/tb/backlog     || echo 0)
    local bl1=$(wc -l 2>/dev/null < $i/var/tmp/tb/backlog.1st || echo 0)
    local blu=$(wc -l 2>/dev/null < $i/var/tmp/tb/backlog.upd || echo 0)

    # "r" image is running
    # " " image is NOT running
    local flags=""
    if __is_running $i ; then
      flags+="r"
    else
      flags+=" "
    fi

    # "S" STOP file
    # "s" STOP in backlog
    if [[ -f $i/var/tmp/tb/STOP ]]; then
      flags+="S"
    else
      if grep -q "^STOP" $i/var/tmp/tb/backlog.1st 2>/dev/null; then
        flags+="s"
      else
        flags+=" "
      fi
    fi

    # result of last run of @system, @world and @preserved-rebuild respectively:
    #
    # upper case: an error occurred
    # lower case: just a package failed
    # "." not yet run
    # " " ok
    check_history $i/var/tmp/tb/@preserved-rebuild.history  p
    check_history $i/var/tmp/tb/@world.history              w
    check_history $i/var/tmp/tb/@system.history             s

    # images during setup are not yet symlinked to ~/run
    local b=$(basename $i)
    [[ -e ~/run/$b ]] && d="~/run" || d="~/img"
    printf "%5i %4i %3i %4.1f %7i %4i %4i %5s %s/%s\n" $compl $fail $bgo $days $bl $blu $bl1 "$flags" "$d" "$b" 2>/dev/null
  done
}


# whatsup.sh -t
# 17.1_desktop-20210102  0:19 m  dev-ros/message_to_tf
# 17.1_desktop_plasma_s  0:36 m  dev-perl/Module-Install
function Tasks()  {
  ts=$(date +%s)
  for i in $images
  do
    PrintImageName $i 30
    if ! __is_running $i ; then
      echo
      continue
    fi

    tsk=$i/var/tmp/tb/task
    if [[ ! -s $tsk ]]; then
      echo
      continue
    fi
    task=$(cat $tsk)

    let "delta = $ts - $(stat -c%Y $tsk)" || true

    if [[ $delta -lt 3600 ]]; then
      let "minutes = $delta / 60 % 60"  || true
      let "seconds = $delta % 60 % 60"  || true
      printf "%3i:%02i m " $minutes $seconds
    else
      let "hours = $delta / 60 / 60"    || true
      let "minutes = $delta / 60 % 60"  || true
      printf "%3i:%02i h " $hours $minutes
    fi

    if [[ ! $task =~ "@" && ! $task =~ "%" && ! $task =~ "#" ]]; then
      echo -n " "
    fi
    echo $task | cut -c1-$cols_task
  done
}


# whatsup.sh -l
#
# 17.1_desktop_plasma_s  0:02 m  >>> AUTOCLEAN: media-sound/toolame:0
# 17.1_systemd-20210123  0:44 m  >>> (1 of 2) sci-libs/fcl-0.5.0
function LastEmergeOperation()  {
  for i in $images
  do
    PrintImageName $i 30
    if ! __is_running $i ; then
      echo
      continue
    fi

    # display the last *started* emerge operation
    tac $i/var/log/emerge.log 2>/dev/null |\
    grep -m 1 -E -e ' >>>| \*\*\* emerge' -e ' \*\*\* terminating.' -e ' ::: completed emerge' |\
    sed -e 's/ \-\-.* / /g' -e 's, to /,,g' -e 's/ emerge / /g' -e 's/ completed / /g' -e 's/ \*\*\* .*/ /g' |\
    perl -wane '
      next if (scalar @F < 2);

      chop ($F[0]);
      my $delta = time() - $F[0];

      if ($delta < 3600) {
        $minutes = $delta / 60 % 60;
        $seconds = $delta % 60 % 60;
        printf ("%3i:%02i m  ", $minutes, $seconds);
      } else  {
        $hours = $delta / 60 / 60;
        $minutes = $delta / 60 % 60;
        # mark long runtimes
        printf ("%3i:%02i h%s ", $hours, $minutes, $delta < 7200 ? " " : "!");
      }
      my $outline = join (" ", @F[1..$#F]);
      print substr ($outline, 1, '"'$cols_task'"');
    '
    echo
  done
}


# whatsup.sh -d
#                                                         1d   2d   3d   4d   5d   6d   7d   8d   9d  10d
# 17.1_no_multilib-j3_debug-20210620-175917            1704 1780 1236 1049 1049  727  454  789
# 17.1_desktop_systemd-j3_debug-20210620-181008        1537 1471 1091  920 1033  917  811  701´
function PackagesPerImagePerRunDay() {
  printf "%55s" ""
  for i in $(seq 1 11); do printf "%4id" $i; done
  echo

  for i in $(ls -d ~/run/* 2>/dev/null | sort -t '-' -k 3,4)
  do
    PrintImageName $i 54

    local start_time=$(getStartTime $i)
    perl -F: -wane '
      BEGIN {
        @packages   = ();  # helds the amount of emerge operations per runday
      }

      my $epoch_time = $F[0];
      next unless (m/::: completed emerge/);

      my $rundays = int( ($epoch_time - '$start_time') / 86400);
      $packages[$rundays]++;

      END {
        if ($#packages >= 0) {
          $packages[$rundays] += 0;
          foreach my $rundays (0..$#packages) {
            ($packages[$rundays]) ? printf "%5i", $packages[$rundays] : printf "    -";
          }
        }
        print "\n";
      }
    ' $i/var/log/emerge.log 2>/dev/null
  done
}

# whatsup.sh -c
# coverage in ~/run : 84 % of past  8 days
# coverage in ~/img : 91 % of past 53 days
function Coverage() {
  local N=$(ls -d /var/db/repos/gentoo/*-*/* | wc -l)
  echo "$N packages in ::gentoo"
  for i in run img
  do
    local n=$(grep -H '::: completed emerge' ~/$i/*/var/log/emerge.log |\
                # handle ::local
                tr -d ':' |\
                awk ' { print $7 } ' |\
                xargs --no-run-if-empty qatom -F "%{CATEGORY}/%{PN}" |\
                sort -u |\
                wc -l)
    local oldest=$(cat ~/$i/*/var/tmp/tb/setup.timestamp 2>/dev/null | sort -u -n | head -n 1)
    local days=$(( ( $(date +%s) - $oldest ) / 3600 / 24 ))
    local perc
    ((perc = 100 * $n / $N))
    printf "coverage in ~/%s : %2i %% of past %2i days" $i $perc $days
    echo
  done
}


# whatsup.sh -p
#
# package revisions x emerge times
# 3006x1 824x2 387x3 197x4 171x5 137x6 154x7 136x8 84x9 79x10 109x11 286x12 6x13 6x14 6x15
function CountEmergesPerPackages()  {
  echo "package revisions x emerge times"

  perl -wane '
    BEGIN {
      my %pet = ();     # package => emerge times
    }

    next unless (m/::: completed emerge/);

    my $pkg = $F[7];
    $pet{$pkg}++;

    END {
      my %h = ();       # pet => occurrence

      for my $key (sort keys %pet)  {
        my $value = $pet{$key};
        $h{$value}++;
      }

      my $total = 0;    # total amount of emerge operations
      my $seen = 0;     #              of packages
      my $max = 0;      # max times of being emerged

      for my $key (sort { $a <=> $b } keys %h)  {
        my $value = $h{$key};
        $seen += $value;
        $total += $key * $value;
        print " ", $value, "x", $key;
        $max = $key if ($max < $key);
      }

      for my $key (sort keys %pet)  {
        print " ", $key if ($max == $pet{$key});
      }
      print "\n\n $seen package revisions in $total emerges\n";
    }
  ' ~/run/*/var/log/emerge.log
}


# whatsup.sh -e
# yyyy-mm-dd   sum   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19  20  21  22  23
#
# 2021-04-31    15   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0  15   0   0   0
# 2021-05-01  2790  28  87  91  41   4  13   0   1  15  29  78  35  62  46  75   9   0 193 104 234 490 508 459 188
function emergeThruput()  {
  perl -we '
      print "yyyy-mm-dd   sum  ";
      foreach my $i (0..23) { printf("%4i", $i) }
      print "\n\n";
      '

  perl -F: -wane '
    BEGIN {
      my %Day = ();
    }
    {
      next unless (m/::: completed emerge/);

      my $epoch_time = $F[0];
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($epoch_time);
      $year += 1900;
      $mon += 1;
      $mon = "0" . $mon if ($mon < 10);
      $mday = "0" . $mday if ($mday < 10);

      my $key = $year . "-" . $mon . "-" . $mday;
      $Day{$key}->{$hour}++;
      $Day{$key}->{"day"}++;
    }

    END {
      for my $key (sort { $a cmp $b } keys %Day)  {
        printf("%s %5i  ", $key, $Day{$key}->{"day"});
        foreach my $hour(0..23) {
          printf("%4i", $Day{$key}->{$hour} ? $Day{$key}->{$hour} : 0);
        }
        print "\n";
      }
    }
  ' $(find ~/img/*/var/log/emerge.log -mtime -15 | sort -t '-' -k 3,4) |\
  tail -n 14
}


#############################################################################
#
# main
#
set -eu
export LANG=C.utf8
unset LC_TIME

source $(dirname $0)/lib.sh

images=$(__list_images)

# cut too long lines of tasks / last emerge op
if tput cols_task 2>/dev/null; then
  ((cols_task = $(tput cols_task) - 38))
else
  cols_task=100
fi

while getopts cdehlopt\? opt
do
  case $opt in
    c)  Coverage                  ;;
    d)  PackagesPerImagePerRunDay ;;
    e)  emergeThruput             ;;
    l)  LastEmergeOperation       ;;
    o)  Overall                   ;;
    p)  CountEmergesPerPackages   ;;
    t)  Tasks                     ;;
  esac
  echo
done
