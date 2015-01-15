#!/bin/bash

reportfail()
{
    echo "Failed...exiting. ($*)" 1>&2
    exit 255
}

try()
{
    eval "$@" || reportfail "$@"
}

[ "root" = "$(whoami)" ] || reportfail "must be root"


default_steps='
  all_steps
'

######## fake step: all_steps

# The purpose of this step is to give
# one target that summarizes all the
# tree/DAGs of steps in this file.

deps_all_steps='
'

check_all_steps()
{
    false
}

do_all_steps()
{
    false
}

######## fake step: block

# The purpose of this steps is so that it can
# be added to other fake steps to block them
# from trying to "do" their dependencies.

deps_block='
'
check_block()
{
    false
}

do_block()
{
    false
}

# {do/check/do1/check1/reset1} {list of steps....} -- params
main()
{
    try abspath="$(cd $(dirname "$0") ; pwd )"
    try cd "$abspath"

    case "$1" in
	check | check1 | 'do' | do1 | reset1)
	    cmd="$1"
	    shift
	    ;;
	*)
	    cmd=check
	    ;;
    esac

    # split remaining params into those before "--" and those after (if any).
    steplist=() # installation/demo steps to process
    while [ "$#" != 0 ]
    do
	p="$1" ; shift
	[ "$p" = "--" ] && break
	func_defined "check_$p" || return
	func_defined "do_$p" || return
	steplist=( "${steplist[@]}" "$p" )
    done
    paramlist=() # params taken one by one by interactive prompts, for one-line shortcuts
    while [ "$#" != 0 ]
    do
	p="$1" ; shift
	paramlist=( "${paramlist[@]}" "$p" )
    done

    [ "${#steplist[@]}" = 0 ] && steplist=( $default_steps )

    for step in "${steplist[@]}"
    do
	echo
	echo "=================  ${cmd}_cmd" "$step"
	"${cmd}_cmd" "$step"
    done
}

read_or_param()
{
    if [ "${#paramlist[@]}" = 0 ]
    then
	read val
    else
	val="${paramlist[0]}"
	paramlist=("${paramlist[@]:1}") # shift array
	echo "(from cmdline): $val"
    fi
}

func_defined()
{
    if ! declare -f "$1" > /dev/null  # function defined?
    then
	echo "Function for step not found: $1" 1>&2
	return 1
    fi
    return 0
}

check1_cmd()
{
    try cd "$abspath"
    local stepname="$1"
    local indent="$2"

    printf "*%-10s %s   " "${indent//  --  /*}" "$indent$stepname"
    if "check_$stepname"
    then
	echo "Done (maybe)"
    else
	echo "Not Done"
    fi
}

already_checked=""
: ${dedup:=yes}
: ${dotout:=/tmp/vnet.dot}
check_cmd()
{
    local stepname="$1"
    local indent="$2"
    local dotlevel="$dotlevel"
    local depstep

    if [ "$dotout" != "" ]; then
	if [ "$dotlevel" = "" ]; then
	    exec 44>"$dotout"
	    echo "strict digraph { " >&44
	    dotlevel=1
	else
	    dotlevel=$(( dotlevel + 1 ))
	fi
    fi

    check1_cmd "$stepname" "$indent"
    if [ "$dedup" = "yes" ]; then
	tmp="${already_checked//$stepname/}"
	[[ "$tmp" == *,,* ]] && return
	already_checked="$already_checked ,$stepname, "
    fi

    # uncomment to have the step source inserted in output
    # eval type "do_${stepname}"

    local deps
    eval 'deps=$deps_'"$stepname"
    for depstep in $deps
    do
	check_cmd "$depstep" "$indent  --  "
	[ "$dotout" = "" ] && continue
	echo "$depstep -> $stepname" >&44
    done

    if [ "$dotout" != "" ] && [ "$dotlevel" = "1" ]; then
	echo "}" >&44
    else
	dotlevel=$(( dotlevel - 1 ))
    fi
}

reset1_cmd()
{
    local stepname="$1"
    local indent="$2"
    echo -n "$indent$stepname   "
    if "reset_$stepname"
    then
	echo "Maybe reset."
    else
	echo "Probably did not reset."
	exit 255
    fi
}

do1_cmd()
{
    try cd "$abspath"
    local stepname="$1"
    local indent="$2"
    echo -n "$indent$stepname   "
    if "do_$stepname"
    then
	if "check_$stepname"
	then
	    echo "Success."
	else
	    echo "Ran but failed check....exiting."
	    exit 255
	fi
    else
	echo "Failed....exiting." 1>&2
	exit 255
    fi
}

do_cmd()
{
    local stepname="$1"
    local indent="$2"

    if "check_$stepname" 
    then
	echo "$indent$stepname :: Probably already done"
	return 0
    fi

    local deps
    eval 'deps=$deps_'"$stepname"
    for depstep in $deps
    do
	do_cmd "$depstep" "$indent  --  "
    done

    do1_cmd "$stepname" "$indent"
}

wait-and-rename-tap()
{
    # wait for a line like this:
    # bash -c echo 1 > /proc/sys/net/ipv4/conf/tap0/proxy_arp

    sbuml-expect "$VM" '*proxy_arp*' 4
    sso="$(sbumlstdout "$VM")"
    gettap="$(tail -n "$lookback" "$sso")"
    # make sure we don't find it next time
    echo $'\n\n\n\n' >>"$sso"

    gettap="${gettap%/proxy_arp*}"
    gettap="${gettap##*/}"  # now it should be something like "tap0"
    rename-tap "$gettap" "$TAP"
}

add-eth1()
{
    VM="$1"
    add-eth1-for-rh80 "$@"
}

add-eth1-for-rh80()
{
    VM="$1"
    IP="$2"
    MAC="$3"
    TAP="$4"

    # grab parameter for tap from previous command line of already launched SBUML
    tapinfo="$(ps aux | grep -m 1 -o 'tuntap,,,[^ ]* ')" # something like: tuntap,,,10.0.3.15
    do-sbumlcmd "sbumlmconsole $VM config eth1=$tapinfo"

    trycount=15
    while sleep 1.23 && (( trycount-- )) ; do
	do-sbumlcmd "sbumlguestexec $VM ifconfig eth1 up $IP netmask 255.255.255.0 hw ether $MAC"
	r="$(do-sbumlcmd "sbumlguestexec $VM ifconfig eth1")"
	[[ "$r" == *UP* ]] && break
    done

    wait-and-rename-tap
    # celebrate:

    #do-sbumlcmd "sbumlguestexec $VM route add default eth1"
    # The next line works, but not sure if we can know for sure that
    # ssh connections from the host VM will always look like they
    # come from 10.0.2.15.  TODO: check closer
    do-sbumlcmd "sbumlguestexec $VM route add -net 10.0.2.0 netmask 255.255.255.0 dev eth1"
    
    do-sbumlcmd "sbumlguestexec $VM ifconfig eth0 \>/dev/vc/1"
    do-sbumlcmd "sbumlguestexec $VM ifconfig eth1 \>/dev/vc/1"

    route add -host "$IP" dev "$TAP"
}

boot-login()
{
    restore-prebooted-rh80vm "$@"
}

restore-prebooted-rh80vm()
{
    VM="$1"
    IP="$2"
    MAC="$3"
    TAP="$4"
    HOSTNAME="$5"

    [ -d "$SBUMLDIR"/machines/$VM ] && return
    # 67880b/ has restarted sshd to get rid of old DNS
    # SNAPSHOT=rh80b-v004-dhcp-config-for-eth0-optional-debugging-e98a8df18164d087
    # SNAPSHOT=rh80b-v005-new-ssh-client-9f37bb3885c1f901
    # SNAPSHOT=rh80b-v008-fetched-in-ssh-7e3c90d59668dd4b
    # SNAPSHOT=rh80b-v008-fetchedin-ssh-ping-etc-e4ec6c12ecc9ff34
    # SNAPSHOT=rh80b-v009-recent-netcat-from-centos-092ab975f5ce39c4
    SNAPSHOT=rh80b-v010-move-nc-to-slash-bin-c4e5ba795eedf50b
    do-sbumlcmd "sbumlrestore $VM $SNAPSHOT -c -sd $SBUMLRESOURCES/"
    # no need to login :-)

    # this removes a default UML specific script that overides too much.
    # Taking this out because current snapshot (f1e6f2) has the standard
    # ifcfg-eth0 for DHCP.
    #do-sbumlcmd "sbumlguestexec $VM rm -f /etc/sysconfig/network-scripts/ifcfg-eth0"

    # removing resolv.conf stops the VM from wasting time (and overruning timeouts) by
    # trying to use an out-of-date server (at Todai!).
    do-sbumlcmd "sbumlguestexec $VM rm -f /etc/resolv.conf"

    do-sbumlcmd "sbumlguestexec $VM hostname $HOSTNAME"
    do-sbumlcmd "sbumlguestexec $VM tar xzvf /h/tmp/ssh.tar.gz -C /root"
    do-sbumlcmd "sbumlguestexec $VM ifconfig eth0 up $IP netmask 255.255.255.0 hw ether $MAC"
    wait-and-rename-tap

    # and yet another workaround.  ifup and ifdown remove the tap devices on the host, so
    # disable for now.
    # Not disabling now...because the current snapshot (f1e6f2) disables
    # calls from ifdown to "if link $dev down"
    #do-sbumlcmd "sbumlguestexec $VM mv /sbin/ifup /sbin/ifup-hide"
    #do-sbumlcmd "sbumlguestexec $VM mv /sbin/ifdown /sbin/ifdown-hide"
}

rename-tap()
{
    ifconfig "$1" down || return
    ip link set "$1" name "$2"
    ifconfig "$2" up
}

do-sbumlcmd()
{
    check_install_sbuml_core || reportfail "SBUML is not installed"
    su "$centosuser" -c "cd $SBUMLDIR; DISPLAY=:0.0 ./sbumlinitdemo -c '$*'"
}

sbumlstdout()
{
    VM="$1"
    echo "$SBUMLDIR/machines/$VM/stdout"
}

sbuml-expect()
{
    VM="$1"
    PAT="$2"
    lookback="$3"
    sso="$(sbumlstdout "$VM")"
    trycount=30
    while ! [ -f "$sso" ] ; do
	sleep 1
	(( trycount-- )) || return 255
    done
    while [[ "$(tail -n "$lookback" "$sso")" != $PAT ]] ; do
	[ -f "$sso" ] || return 255 # VM was removed
	sleep 0.2
	sso="$(sbumlstdout "$VM")"
    done
    return 0
}




cat >/tmp/utils.sh <<'EOFlong'
util-remove-test-ports()
{
    ovs-vsctl del-port br0 if-tap0
    ovs-vsctl del-port br0 if-tap1
    ovs-vsctl show
}

util-add-ports-for-rspec()
{
    ( 
	set -x
	for i in $(ifconfig | grep -o 'if-v[0-9]')
	do
	    ovs-vsctl add-port br0 $i
	done
	ovs-vsctl show
    )
}

util-cmd-in-all-vms()
{
    for i in 91 92 93
    do
	ssh root@192.168.2.$i "$*"
    done
}

util-from-router-set-all-etc-wakame-vnet()
{
    for i in 91 92 93
    do
	ssh root@192.168.2.$i <<EOF
stop vnet-vna
stop vnet-vnmgr
stop vnet-webapi
cd /etc/openvnet
sed -i 's/127.0.0.1/192.168.2.91/' common.conf vnmgr.conf webapi.conf
sed -i 's/127.0.0.1/192.168.2.$i/' vna.conf
sed -i 's/id "vna"/id "vna${i#9}"/' vna.conf
EOF
    done
}

util-from-router-set-all-taps()
{
    for i in 91 92 93
    do
	ssh root@192.168.2.$i "$(cat /tmp/utils.sh) ; util-remove-test-ports ; util-add-ports-for-rspec "
    done
}

util-from-router-set-br0-macaddr() # is this necessary?
{
    for i in 91 92 93
    do
	echo "doing: $i"
	ssh root@192.168.2.$i "ifconfig br0 | grep HW ; ifconfig br0 hw ether 02:01:00:00:00:0${i#9}"
    done
}

util-continuious-set-br0-macaddr()
{
    while sleep 2
    do
	util-from-router-set-br0-macaddr
    done
}

util-from-router-do-all()
{
    util-from-router-set-all-taps
    util-from-router-set-all-etc-wakame-vnet
    util-from-router-set-br0-macaddr
}

EOFlong




echo $$ >>/tmp/test-vnet-pids
cat >/tmp/test-vnet-killall.sh <<'EOF'
for i in $(cat /tmp/test-vnet-pids)
do
  kill $i
done
EOF

main "$@"

pids="$(cat /tmp/test-vnet-pids)"
echo "$pids" | grep -v "$$" >/tmp/test-vnet-pids
