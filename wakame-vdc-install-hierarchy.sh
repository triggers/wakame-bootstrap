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
   start_wakame_vdc
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

######## confirm_bridge_already_setup

# the check_ part must be run

deps_confirm_bridge_already_setup='
'

check_confirm_bridge_already_setup()
{
    get_default_route && get_ip_mask "$INTERFACE"
    (
	set -e
	which brctl >/dev/null
	[ "$INTERFACE" = "br0" ]
    ) || {
	echo
	echo "This script requires the bridge to be set up first,"
	echo "which should be done manually.  A script to do this"
	echo "has been prepared at /tmp/setup-bridge.sh, assuming"
	echo "IP=$IPADDR, MASK=$MASK, GATEWAY=$GATEWAY and"
	echo "that the outgoing interface is $INTERFACE.  Inspect"
	echo "the script carefully for correctness before running."
	cat >/tmp/setup-bridge.sh <<EOF
set -x
yum install -y bridge-utils
which brctl || exit 255

cat > /etc/sysconfig/network-scripts/ifcfg-br0 <<EOF2
    DEVICE=br0
    TYPE=Bridge
    BOOTPROTO=static
    ONBOOT=yes
    NM_CONTROLLED=no
    IPADDR=$IPADDR
    NETMASK=$MASK
    GATEWAY=$GATEWAY
    DNS1=8.8.8.8
    DELAY=0
EOF2

cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF2
    DEVICE="$INTERFACE"
    ONBOOT="yes"
    BRIDGE=br0
    NM_CONTROLLED=no
EOF2

echo "Will reset networking after 15 seconds"
echo "Press ^C to cancel."
sleep 15
EOF
	chmod +x /tmp/setup-bridge.sh
	return 255
    } 1>&2
}

do_confirm_bridge_already_setup()
{
    :
}

get_default_route()
{
    while read iface dest gway rest; do
	if [ "$dest" = "00000000" ]; then
	    export INTERFACE="$iface"
	    export GATEWAY="$gway"
	    break
	fi
    done </proc/net/route
    [ "$GATEWAY" = "" ] && return 255
    GATEWAY="$({ read -n 2 dd; read -n 2 cc; read -n 2 bb; read -n 2 aa
                 echo "$(( 0x$aa )).$(( 0x$bb )).$(( 0x$cc )).$(( 0x$dd ))"
               } <<<"$GATEWAY" )"
}

get_ip_mask()
{
    iface="$1"
    cmdout="$(ifconfig "$iface")"
    read IPADDR ignore <<<"${cmdout#*inet addr:}"
    read MASK ignore <<<"${cmdout#*Mask:}"
}


######## lets_get_started

deps_lets_get_started='
   install_dcmgr
   install_hva
   install_webui
'
check_lets_get_started()
{
    [ -f /tmp/did_lets_get_started ]
}

do_lets_get_started()
{
    # just a wrapper to call the deps
    touch /tmp/did_lets_get_started
}

######## yum_repository_setup

deps_yum_repository_setup='
'

check_yum_repository_setup()
{
    #[ -f /etc/yum.repos.d/openvz.repo ] && \
    
    [ -f /etc/yum.repos.d/wakame-vdc.repo ] && \
	[ -f /etc/yum.repos.d/epel.repo ] && \
	[ -f /etc/yum.repos.d/epel-testing.repo ]
}

do_yum_repository_setup()
{
    curl -o /etc/yum.repos.d/wakame-vdc.repo -R https://raw.githubusercontent.com/axsh/wakame-vdc/master/rpmbuild/wakame-vdc.repo

    #    curl -o /etc/yum.repos.d/openvz.repo -R https://raw.githubusercontent.com/axsh/wakame-vdc/master/rpmbuild/openvz.repo

    #    yum install -y epel-release && touch /tmp/installed_epel_release

    # from https://github.com/wakameci/buildbook-rhel6/blob/master/epel-release/xexecscript.d/epel-release.sh
    rpm -Uvh http://ftp.jaist.ac.jp/pub/Linux/Fedora/epel/6/i386/epel-release-6-8.noarch.rpm
    # workaround 2014/10/17
    #
    # in order escape below error
    # > Error: Cannot retrieve metalink for repository: epel. Please verify its path and try again
    #
    sed -i \
	-e 's,^#baseurl,baseurl,' \
	-e 's,^mirrorlist=,#mirrorlist=,' \
	-e 's,http://download.fedoraproject.org/pub/epel/,http://ftp.jaist.ac.jp/pub/Linux/Fedora/epel/,' \
	/etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel-testing.repo
}


######## install_dcmgr

deps_install_dcmgr='
   yum_repository_setup
'

check_install_dcmgr()
{
    [ -f /tmp/installed_dcmgr ]
}

do_install_dcmgr()
{
    yum install -y wakame-vdc-dcmgr-vmapp-config && \
	touch /tmp/installed_dcmgr
}

######## install_hva

deps_install_hva='
   yum_repository_setup
'

check_install_hva()
{
    [ -f /tmp/installed_hva ]
}

do_install_hva()
{
    yum install -y wakame-vdc-hva-kvm-vmapp-config && touch /tmp/installed_hva
}


######## install_webui

deps_install_webui='
   yum_repository_setup
'

check_install_webui()
{
    [ -f /tmp/installed_webui ]
}

do_install_webui()
{
    yum install -y wakame-vdc-webui-vmapp-config && touch /tmp/installed_webui
}

######## configuration

deps_configuration='
   lets_get_started
   service_configs
   create_vdc_database
   register_hva
   register_image
   register_network
   configure_gui
'

check_configuration()
{
    [ -f /tmp/did_configuration ]
}

do_configuration()
{
    touch /tmp/did_configuration
}


######## service_configs

deps_service_configs='
'

service_config_files=(
    /opt/axsh/wakame-vdc/dcmgr/config/dcmgr.conf.example:/etc/wakame-vdc/dcmgr.conf

    /opt/axsh/wakame-vdc/dcmgr/config/hva.conf.example:/etc/wakame-vdc/hva.conf

    /opt/axsh/wakame-vdc/frontend/dcmgr_gui/config/database.yml.example:/etc/wakame-vdc/dcmgr_gui/database.yml

    /opt/axsh/wakame-vdc/frontend/dcmgr_gui/config/dcmgr_gui.yml.example:/etc/wakame-vdc/dcmgr_gui/dcmgr_gui.yml

    /opt/axsh/wakame-vdc/frontend/dcmgr_gui/config/instance_spec.yml.example:/etc/wakame-vdc/dcmgr_gui/instance_spec.yml

    /opt/axsh/wakame-vdc/frontend/dcmgr_gui/config/load_balancer_spec.yml.example:/etc/wakame-vdc/dcmgr_gui/load_balancer_spec.yml
)

check_service_configs()
{
    for f in "${service_config_files[@]}" ; do
	[ -f "${f#*:}" ] || return 255
    done
    return 0
}

do_service_configs()
{
    for f in "${service_config_files[@]}" ; do
	cp "${f%:*}" "${f#*:}"
    done
}

######## create_vdc_database

deps_create_vdc_database='
'

check_create_vdc_database() {
    [ -f /tmp/created_vdc_database ]
}

do_create_vdc_database()
{
    service mysqld start
    mysqladmin -uroot create wakame_dcmgr
    cd /opt/axsh/wakame-vdc/dcmgr
    /opt/axsh/wakame-vdc/ruby/bin/rake db:up || return
    touch /tmp/created_vdc_database
}

######## register_hva


deps_register_hva='
'

check_register_hva()
{
    [ -f /tmp/did_register_hva ]
}

do_register_hva()
{
    uncomment 'NODE_ID=demo1' '/etc/default/vdc-hva' || return
    
    /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage host add hva.demo1 \
       --uuid hn-demo1 \
       --display-name "demo HVA 1" \
       --cpu-cores 100 \
       --memory-size 10240 \
       --hypervisor kvm \
       --arch x86_64 \
       --disk-space 102400 \
       --force || return
    
    touch /tmp/did_register_hva
}

function uncomment() {
  local commented_line=$1
  local files=$2

  sudo sed -i -e "s/^#\\(${commented_line}\\)/\\1/" ${files}
}

######## download_image

deps_download_image='
'

check_download_image()
{
    [ -f /var/lib/wakame-vdc/images/ubuntu-lucid-kvm-md-32.raw.gz ]
}

do_download_image()
{
    sudo mkdir -p /var/lib/wakame-vdc/images
    (
	cd /var/lib/wakame-vdc/images
	sudo curl -O http://dlc.wakame.axsh.jp.s3.amazonaws.com/demo/vmimage/ubuntu-lucid-kvm-md-32.raw.gz
    )
}


######## register_image

deps_register_image='
   download_image
'

check_register_image()
{
    [ -f /tmp/register_image ]
}

do_register_image()
{
    /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage backupstorage add \
      --uuid bkst-local \
      --display-name "local storage" \
      --base-uri "file:///var/lib/wakame-vdc/images/" \
      --storage-type local \
      --description "storage on the local filesystem" || return

    /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage backupobject add \
      --uuid bo-lucid5d \
      --display-name "Ubuntu 10.04 (Lucid Lynx) root partition" \
      --storage-id bkst-local \
      --object-key ubuntu-lucid-kvm-md-32.raw.gz \
      --size 149084 \
      --allocation-size 359940 \
      --container-format gz \
      --checksum 1f841b195e0fdfd4342709f77325ce29 || return

    touch /tmp/register_image
}


######## register_network

deps_register_network='
'

check_register_network()
{
    [ -f /tmp/register_network ]
}

do_register_network()
{
    (
	set -e
	/opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage network add \
						  --uuid nw-demo1 \
						  --ipv4-network 10.0.2.15 \
						  --prefix 24 \
						  --ipv4-gw 10.0.2.2 \
						  --dns 8.8.8.8 \
						  --account-id a-shpoolxx \
						  --display-name "demo network"

	/opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage network dhcp addrange nw-demo1 10.0.2.100 10.0.2.150

	# /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage network reserve nw-demo1 --ipv4 192.168.3.100

	/opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage macrange add 525400 1 ffffff --uuid mr-demomacs

	/opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage network dc add public --uuid dcn-public --description "the network instances are started in"

	/opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage network dc add-network-mode public securitygroup

	/opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage network forward nw-demo1 public
    )
    touch /tmp/register_network
    # TODO: worry about other IP ranges and eth1 vs eth0, etc.
}


######## configure_gui

deps_configure_gui='
'

check_configure_gui()
{
    [ -f /tmp/configure_gui ]
}

do_configure_gui()
{
    (
	set -e
	mysqladmin -uroot create wakame_dcmgr_gui
	cd /opt/axsh/wakame-vdc/frontend/dcmgr_gui/
	/opt/axsh/wakame-vdc/ruby/bin/rake db:init

	/opt/axsh/wakame-vdc/frontend/dcmgr_gui/bin/gui-manage account add --name default --uuid a-shpoolxx
	/opt/axsh/wakame-vdc/frontend/dcmgr_gui/bin/gui-manage user add --name "demo user" --uuid u-demo --password demo --login-id demo
	/opt/axsh/wakame-vdc/frontend/dcmgr_gui/bin/gui-manage user associate u-demo --account-ids a-shpoolxx
    )
    touch /tmp/configure_gui
}

######## start_required_services

deps_start_required_services='
'

check_start_required_services()
{
    {
	service rabbitmq-server status || return
	service mysqld start || return
    } >/dev/null
}

do_start_required_services()
{
    service rabbitmq-server start
    service mysqld start
}

######## start_wakame_vdc

deps_start_wakame_vdc='
   confirm_bridge_already_setup
   configuration
   start_required_services
'

wakame_jobs=(
    vdc-dcmgr
    vdc-collector
    vdc-hva
    vdc-webui
)

check_start_wakame_vdc()
{
    for j in "${wakame_jobs[@]}"; do
	[[ "$(status $j 2>/dev/null)" == *stop* ]] && return 255
    done
    return 0
}

do_start_wakame_vdc()
{
    for j in "${wakame_jobs[@]}"; do
	start $j
    done
}

reset_start_wakame_vdc()
{
    for j in "${wakame_jobs[@]}"; do
	stop $j
    done
}

######################### dispatching code ################################

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

main "$@"
