#!/bin/bash
# This is a tweaked version of this script https://github.com/nbq/hifi-compile-scripts/ for use as a cron job to auto-update the hifi stack

# Home Directory for HifiUser
HIFIDIR="/usr/local/hifi"
# Last Compile Backup Directory
LASTCOMPILE="$HIFIDIR/last-compile"
# Runtime Directory Location
RUNDIR="$HIFIDIR/run"
# Log Directory
LOGSDIR="$HIFIDIR/logs"
# Source Storage Dir
SRCDIR="/usr/local/src"

## Functions ##
function checkroot {
  [ `whoami` = root ] || { echo "Please run as root"; exit 1; }
}

function writecommands {
# Always rewrite just incase something changed
cat <<EOF > /etc/profile.d/coal.sh
alias compilehifi='bash <(curl -Ls https://raw.githubusercontent.com/nbq/hifi-compile-scripts/master/centos7-compile-hifi.sh)'
alias recompilehifi='bash <(curl -Ls https://raw.githubusercontent.com/nbq/hifi-compile-scripts/master/centos7-recompile-hifi.sh)'
alias runhifi='bash <(curl -Ls https://raw.githubusercontent.com/nbq/hifi-compile-scripts/master/centos7-run-hifi.sh)'
alias killhifi='bash <(curl -Ls https://raw.githubusercontent.com/nbq/hifi-compile-scripts/master/centos7-kill-hifi.sh)'
EOF
}

function killrunning {
  echo "Killing Running Processess"
  pkill -9 -f "[d]omain-server" > /dev/null 2>&1
  pkill -9 -f "[a]ssignment-client" > /dev/null 2>&1
}


function compilehifi {
  # NOTE - This currently assumes /usr/local/src and does not move forward if the source dir does not exist - todo: fix
  if [[ -d "$SRCDIR" ]]; then
    pushd $SRCDIR > /dev/null

    # handle install and compile of cmake
    if [[ ! -f "/usr/bin/cmake"  ]]; then
      handlecmake
    fi

    if [[ ! -d "highfidelity" ]]; then
      mkdir highfidelity
    fi

    cd highfidelity

    if [[ ! -d "hifi" ]]; then
      git clone https://github.com/highfidelity/hifi.git
      NEWHIFI=1
    fi
    
    # popd src
    popd > /dev/null
    pushd $SRCDIR/highfidelity/hifi > /dev/null 

    # Future todo - add a forcable call to the shell script to override this
    if [[ $(git pull) =~ "Already up-to-date." ]]; then
      echo "[$(date)]: Already up to date with last commit." >> $LOGSDIR/cron_log.log
      echo "Already up to date with last commit."
      exit 0
    else
      NEWHIFI=1
    fi

    if [[ $NEWHIFI -eq 1 ]]; then
      echo "[$(date)]: Source needs compiling." >> $LOGSDIR/cron_log.log
      echo "Source needs compiling."
      # commented out so compile can run behind the scenes, to maximise uptime
      # killrunning
      # we are still assumed to be in hifi directory
      if [[ -d "build" ]]; then
        rm -rf build/*
      else
        mkdir build
      fi
      cd build
      cmake -DGET_LIBOVR=1 ..
	  make domain-server > $LOGSDIR/last_compile.log
		if [ $? -eq 0 ]
		then
			echo "[$(date)]: Build was successful!" > $LOGSDIR/last_compile.log
			echo "[$(date)]: Build was successful!" >> $LOGSDIR/cron_log.log
			echo "Build was successful!"
  
		else
			echo "[$(date)]: Build Failed!" >> $LOGSDIR/last_compile.log
			echo "[$(date)]: Build Failed!" >> $LOGSDIR/cron_log.log
			echo "Build Failed!"
			exit 1
		fi
	
	  make assignment-client >> $LOGSDIR/last_compile.log
		if [ $? -eq 0 ]
		then
			echo "[$(date)]: Build was successful!" >> $LOGSDIR/last_compile.log
			echo "[$(date)]: Build was successful!" >> $LOGSDIR/cron_log.log
			echo "Build was successful!"
  
		else
			echo "[$(date)]: Build Failed!" >> $LOGSDIR/last_compile.log
			echo "[$(date)]: Build Failed!" >> $LOGSDIR/cron_log.log
			echo "Build Failed!"
			exit 1
		fi

      setwebperm
    fi 
    # ^ Ending the git pull check

    # popd on hifi source dir
    popd > /dev/null
  fi
}

function handlerunhifi {
  echo "Running your HiFi Stack as user hifi"
  echo "To update your install later, just type 'compilehifi' to begin this safe process again - NO DATA IS LOST"
  export -f runashifi
  su hifi -c "bash -c runashifi"
  exit 0
}
function runashifi {
  # Everything here is run as the user hifi
  TIMESTAMP=$(date '+%F')
  HIFIDIR=/usr/local/hifi
  HIFIRUNDIR=$HIFIDIR/run
  HIFILOGDIR=$HIFIDIR/logs
  cd $HIFIRUNDIR
  ./domain-server &>> $HIFILOGDIR/domain-$TIMESTAMP.log&
  ./assignment-client -n 5 &>> $HIFILOGDIR/assignment-$TIMESTAMP.log&
}
function killrunning {
  echo "Killing Running Processess"
  pkill -9 -f "[d]omain-server" > /dev/null 2>&1
  pkill -9 -f "[a]ssignment-client" > /dev/null 2>&1
}

function setwebperm {
  chown -R hifi:hifi $SRCDIR/highfidelity/hifi/domain-server/resources/web
}

function changeowner  {
  if [ -d "$HIFIDIR" ]; then
    chown -R hifi:hifi $HIFIDIR
  fi  
}

function movehifi {
  setwebperm
  DSDIR="$SRCDIR/highfidelity/hifi/build/domain-server"
  ACDIR="$SRCDIR/highfidelity/hifi/build/assignment-client"
  cp $DSDIR/domain-server $RUNDIR
  cp -R $DSDIR/resources $RUNDIR
  cp $ACDIR/assignment-client $RUNDIR
  changeowner
}

# Make sure only root can run this
checkroot


# Deal with the source code and compile highfidelity
compilehifi

# Kill running instance
killrunning

# Copy new binaries then change owner
movehifi

# Copy commands to be run to .bashrc
writecommands

# Handle re-running the hifi stack as needed here
handlerunhifi
