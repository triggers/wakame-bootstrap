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

main "$@"
