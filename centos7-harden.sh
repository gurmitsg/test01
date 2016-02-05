#!/bin/bash
# Version 0.1 29-Jan-2016 - Gurmit - Created
# Version 0.2 02-Feb-2016 - Gurmit - Fixed for undefined mountpoints
# Version 0.2.1 02-Feb-2016 - Gurmit - Removed hard_1.2.6 - Verify Package Integrity Using RPM (Not Scored)
# 

debug=0
HARDEN_LOG=/tmp/harden.log.$$
HARDEN_OUTPUT=/tmp/harden.out.$$

function print_debug
{
    if [ "$debug" -gt "0" ]; then printf "\nDEBUG: $1"; fi
}


function mountifnot
{
    debug=1
    mnt_dir=$1
    if [ -z "`mount|awk '{print $3}'|grep -x $mnt_dir`" ]; then
        print_debug "Mounting $mnt_dir"
        mount $mnt_dir
    fi
}


function util_chk_fstab
{
    fs=$1
    chkfs=`grep "[[:space:]]$fs[[:space:]]" /etc/fstab | wc -l`
    if [ "$chkfs" -eq "1" ]; then
        echo "OK"
    elif [ "$chkfs" -eq "0" ]; then
        echo "NOT_OK"
    else
        echo "ERROR"
    fi
}



function util_chk_mnt_opts
{
    source=$1
    fs=$2
    fs_opts=$3
    
    if [ "$source" == "fstab" ]; then
        CMD="cat /etc/fstab | gawk '\$2 == \"$fs\" {print \$0}'"
    elif [ "$source" == "mount" ]; then
        CMD="mount | gawk '\$3 == \"$fs\" {print \$0}'"
    fi
        
    for opt in $fs_opts
    do
        CMD="$CMD | grep $opt"
    done

    if [ -z "`eval $CMD`" ]; then
        echo "NOT_OK"
    else
        echo "OK"
    fi
}


function util_chk_bind
{
    target=$1
    source=$2
    if [ -z "`grep -e "^$target[[:space:]]" /etc/fstab | grep $source`" ]; then
        echo "NOT_OK"
    else
        echo "OK"
    fi
}


function util_chk_configvalue_nodelimeter
{
    configfile=$1
    parameter=$2
    #val=`grep "^$parameter " $configfile | gawk '{print \$2}'`
    val=`grep "^$parameter" $configfile | sed 's/[[:space:]]\+/:/g' | gawk -F\: '{print $2}'`
    echo $val
}

function util_set_configvalue_nodelimeter
{
    configfile=$1
    parameter=$2
    val=$3

    if [[ -z `grep "^$parameter" $configfile` ]]; then
        echo "$parameter $val" >> $configfile
    else
        sed -i "s/^${parameter}.*/${parameter} ${val}/" $configfile
    fi
}



function util_chk_configvalue
{
    configfile=$1
    parameter=$2
    space=$3
    if [[ $space == "TRUE" ]]; then
        val=`grep "^$parameter = " $configfile | gawk -F\= '{print \$2}' | tr -d '[[:space:]]'`
    else
        val=`grep ^$parameter= $configfile | gawk -F\= '{print \$2}'`
    fi
    echo "$val"
}

function util_set_configvalue
{
    configfile=$1
    parameter=$2
    val=$3
    space=$4
    if [[ $space == "TRUE" ]]; then
        if [[ -z `grep "^$parameter = " $configfile` ]]; then
            echo "$parameter = $val" >> $configfile
        else
            sed -i "s/^${parameter} = .*/${parameter} = ${val}/" $configfile
        fi
    else
        if [[ -z `grep ^$parameter= $configfile` ]]; then
            echo "$parameter=$val" >> $configfile
        else
            sed -i "s/^${parameter}=.*/${parameter}=${val}/" $configfile
        fi
    fi
}


function util_chk_rpmerase
{
    rpm_check=$1
    if [[ -z `rpm -q $rpm_check | grep ^$rpm_check` ]]; then 
        echo "OK"; 
    else 
        echo "NOT_OK"; 
    fi 
}


function util_chk_svcdisable
{
    svc=$1
    if [[ -z `systemctl list-unit-files | grep enabled | grep $svc` ]]; then
        echo "OK"
    else
        echo "NOT_OK"
    fi
}


function sysctl_match
{
    var=$(declare -p "$1")
    eval "declare -A sysList="${var#*=}
    match=TRUE

    for i in "${!sysList[@]}"
    do
        parameter=$i
        val=${sysList[$i]}
        #printf "\nparameter  : $parameter, value: $val\n"
        if [[ -z `/sbin/sysctl $parameter | grep "$parameter = $val"` ]]; then
            match=FALSE
            break
        fi
    done
    if [[ $match == "TRUE" ]]; then
        echo "OK";
    else
        echo "NOT_OK";
    fi
}


function sysctl_fix
{
    var=$(declare -p "$1")
    eval "declare -A sysList="${var#*=}

    for i in "${!sysList[@]}"
    do
        parameter=$i
        val=${sysList[$i]}
        #printf "\nparameter  : $parameter, value: $val\n"
        util_set_configvalue /etc/sysctl.conf $parameter $val
        /sbin/sysctl -w $parameter=$val >> $HARDEN_LOG
    done    

    /sbin/sysctl -w net.ipv4.route.flush=1 >> $HARDEN_LOG
}


function hard_1.1.01
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Create Separate Partition for /tmp (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi
    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_fstab /tmp)
        if [ "$check_status" == "NOT_OK" ]; then
	    if [[ ! -z "$tmp_mntpt" ]]; then
                printf "\n$fname: Fixing"
                echo -e "$tmp_mntpt\t/tmp\txfs\tdefaults" >> /etc/fstab
	    else
                printf "\n$fname:UserFix:Mountpoint for /tmp not defined"
	    fi
        fi
        mountifnot /tmp
    fi
    check_status=$(util_chk_fstab /tmp)
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.1.02
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Set nodev,nosuid,noexec option for /tmp Partition (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi
    if [ $cmd == "fix" ]; then
        check_status=$(util_chk_mnt_opts fstab /tmp "nodev nosuid noexec") 
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"    
            sed -i '/[[:space:]]\/tmp[[:space:]]/{/nodev/!s/\S\S*/&,nodev/4}' /etc/fstab
            sed -i '/[[:space:]]\/tmp[[:space:]]/{/nosuid/!s/\S\S*/&,nosuid/4}' /etc/fstab
            sed -i '/[[:space:]]\/tmp[[:space:]]/{/noexec/!s/\S\S*/&,noexec/4}' /etc/fstab
            mountifnot /tmp
            mount -o remount /tmp
        fi
    fi
    check_status=$(util_chk_mnt_opts fstab /tmp "nodev nosuid noexec") 
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.1.05
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Create Separate Partition for /var (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_fstab /var)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname:UserFix:Requires single-user mode: "
            printf "Add to /etc/fstab: $var_mntpt\t/var\txfs\tdefaults"
            #echo -e "$var_mntpt\t/var\txfs\tdefaults" >> /etc/fstab
        fi
    fi
    check_status=$(util_chk_fstab /var)
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.1.06
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Bind Mount the /var/tmp directory to /tmp (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_bind /tmp /var/tmp)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            echo -e "/tmp\t/var/tmp\tnone\tbind\t0 0" >> /etc/fstab
            mkdir /var/tmp
        fi
        mountifnot /var/tmp
    fi
    check_status=$(util_chk_bind /tmp /var/tmp)
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.1.07
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Create Separate Partition for /var/log (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_fstab /var/log)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname:UserFix:Requires single-user mode): "
            printf "Add to /etc/fstab: $varlog_mntpt\t/var/log\txfs\tdefaults"
            #echo -e "$varlog_mntpt\t/var/log\txfs\tdefaults" >> /etc/fstab
        fi
    fi
    check_status=$(util_chk_fstab /var/log)
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.1.09
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Create Separate Partition for /home (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_fstab /home)
        if [ "$check_status" == "NOT_OK" ]; then
	    if [[ ! -z "$home_mntpt" ]]; then
                printf "\n$fname: Fixing"
                echo -e "$home_mntpt\t/home\txfs\tdefaults" >> /etc/fstab
	    else
                printf "\n$fname:UserFix:Mountpoint for /home not defined"
	    fi
        fi
        mountifnot /home
    fi
    check_status=$(util_chk_fstab /home)
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.1.10
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Add nodev option to /home (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ $cmd == "fix" ]; then
        check_status=$(util_chk_mnt_opts fstab /home "nodev")
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sed -i '/[[:space:]]\/home[[:space:]]/{/nodev/!s/\S\S*/&,nodev/4}' /etc/fstab
            mountifnot /home
            mount -o remount /home
        fi
    fi
    check_status=$(util_chk_mnt_opts fstab /home "nodev")
    printf "\n$fname:$check_status: $helpout"
}



function hard_1.1.14
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Add nodev,nosuid,noexec Option to /dev/shm Partition (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_mnt_opts mount /dev/shm "nodev nosuid noexec")
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            size=`df -Th | grep /dev/shm | gawk '{print $3}'`
            echo -e "tmpfs\t/dev/shm\ttmpfs\tnodev,nosuid,noexec,size=$size" >> /etc/fstab
        fi
        mountifnot /dev/shm
        mount -o remount /dev/shm
    fi
    
    check_status=$(util_chk_mnt_opts mount /dev/shm "nodev nosuid noexec")
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.1.17
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Set Sticky Bit on All World-Writable Directories (Scored)";
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout";
        return
    fi

    function check
    {
        if [ -z "`df --local -P | awk {'if (NR!=1) print $6'} | xargs -I '{}' find '{}' -xdev -type d \( -perm -0002 -a ! -perm -1000 \) 2>/dev/null`" ]; then
            echo "OK"
        else
            echo "NOT_OK"
        fi
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            df --local -P | awk {'if (NR!=1) print $6'} | xargs -I '{}' find '{}' -xdev -type d \( -perm -0002 -a ! -perm -1000 \) 2>/dev/null | xargs chmod a+t
        fi
    fi
    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_1.1.18
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    fslist="cramfs freevxfs jffs2 hfs hfsplus squashfs udf"
    helpout="Disable Mounting of $fslist Filesystems (Not Scored) - (Issue udf: modprobe -n -v udf)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check
    {
        fixed="TRUE"
        for fs in $fslist
        do
            if !( [[ -z `lsmod | grep $fs` ]] && [[ `modprobe -n -v $fs 2>/dev/null | grep ^install | sed 's/[[:space:]]$//'` == "install /bin/true" ]] ); then
                echo "NOT_OK"
                return
            fi
        done
        echo "OK"
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            modfile=/etc/modprobe.d/CIS.conf
            if [[ -f $modfile ]]; then
                cp -p $modfile $modfile.`date +%s`
            fi
            cp /dev/null $modfile
            for fs in $fslist
            do
                echo "install $fs /bin/true" >> $modfile
            done
        fi
    fi
    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_1.2.3
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Verify that gpgcheck is Globally Activated (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        if [[ $(util_chk_configvalue /etc/yum.conf gpgcheck) == 1 ]]; then check_status="OK"; else check_status="NOT_OK"; fi
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            util_set_configvalue /etc/yum.conf gpgcheck 1
        fi
    fi
    
    if [[ $(util_chk_configvalue /etc/yum.conf gpgcheck) == 1 ]]; then check_status="OK"; else check_status="NOT_OK"; fi
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.2.4
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable the rhnsd Daemon (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        if [[ -z `systemctl list-unit-files | grep enabled | egrep 'rhnsd|yum-updatesd'` ]]; then check_status="OK"; else check_status="NOT_OK"; fi
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            if [[ ! -z `systemctl list-unit-files | grep enabled | grep rhnsd` ]]; then 
                systemctl disable rhnsd
            fi
            if [[ ! -z `systemctl list-unit-files | grep enabled | grep yum-updatesd` ]]; then 
                systemctl disable yum-updatesd
            fi
        fi
    fi

    if [[ -z `systemctl list-unit-files | grep enabled | egrep 'rhnsd|yum-updatesd'` ]]; then check_status="OK"; else check_status="NOT_OK"; fi
    printf "\n$fname:$check_status: $helpout"
}




function hard_1.3.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Install AIDE (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        if [[ ! -z `rpm -q aide | grep ^aide` ]] && [[ -f /var/lib/aide/aide.db.gz ]]; then check_status="OK"; else check_status="NOT_OK"; fi
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            if [[ -z `rpm -q aide | grep ^aide` ]]; then
                yum -y install aide >> $HARDEN_LOG
            fi
            if [[ ! -f /var/lib/aide/aide.db.gz ]]; then
                /usr/sbin/aide --init -B 'database_out=file:/var/lib/aide/aide.db.gz' >> $HARDEN_LOG 2>&1
            fi
        fi
    fi

    if [[ ! -z `rpm -q aide | grep ^aide` ]] && [[ -f /var/lib/aide/aide.db.gz ]]; then check_status="OK"; else check_status="NOT_OK"; fi
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.3.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Implement Periodic Execution of File Integrity (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        if [[ ! -z `crontab -u root -l 2>/dev/null | grep -w aide` ]]; then check_status="OK"; else check_status="NOT_OK"; fi
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            echo "# AIDE" >> /var/spool/cron/root
            echo "0 5 * * * /usr/sbin/aide --check" >> /var/spool/cron/root
        fi
    fi

    if [[ ! -z `crontab -u root -l 2>/dev/null | grep -w aide` ]]; then check_status="OK"; else check_status="NOT_OK"; fi
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.4.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Ensure SELinux is not disabled in /boot/grub2/grub.cfg (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ -z `egrep "selinux=0|enforcing=0" /boot/grub2/grub.cfg` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sed -i -e '/^selinux=0/d' -e '/^enforcing=0/d' /boot/grub2/grub.cfg
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_1.4.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Set the SELinux State (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ $(util_chk_configvalue /etc/selinux/config SELINUX) == "enforcing" ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            util_set_configvalue /etc/selinux/config SELINUX enforcing
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_1.4.3
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Set the SELinux Policy (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ $(util_chk_configvalue /etc/selinux/config SELINUXTYPE) == "targeted" ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            util_set_configvalue /etc/selinux/config SELINUXTYPE targeted
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.4.4
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove SETroubleshoot (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase setroubleshoot)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase setroubleshoot >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase setroubleshoot)
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.4.5
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove MCS Translation Service (mcstrans) (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase mcstrans)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase mcstrans >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase mcstrans)
    printf "\n$fname:$check_status: $helpout"
}


function hard_1.4.6
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Check for Unconfined Daemons (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ -z `ps -eZ | egrep "initrc" | egrep -vw "tr|ps|egrep|bash|awk" | tr ':' ' ' | awk '{print $NF }'` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            proclist=`ps -eZ | egrep "initrc" | egrep -vw "tr|ps|egrep|bash|awk"  | tr ':' ' ' | awk '{print $NF }' | tr '\n\' ' '` 
            printf "\n$fname:UserFix: $proclist"
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_1.5.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Set User/Group Owner on /boot/grub2/grub.cfg (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ ! -z `stat -L -c "%u %g" /boot/grub2/grub.cfg | egrep "0 0"` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            chown root:root /boot/grub2/grub.cfg
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_1.5.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Set Permissions on /boot/grub2/grub.cfg (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ ! -z `stat -L -c "%a" /boot/grub2/grub.cfg | egrep ".00"` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            chmod og-rwx /boot/grub2/grub.cfg
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_1.6.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Restrict Core Dumps (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ `grep "hard core" /etc/security/limits.conf` == "hard core 0" ]] && [[ `sysctl fs.suid_dumpable` == "fs.suid_dumpable = 0" ]]; then 
                     echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            if [[ `grep "hard core" /etc/security/limits.conf` != "hard core 0" ]]; then
                sed -i '/^hard core/d' /etc/security/limits.conf
                echo "hard core 0" >> /etc/security/limits.conf
            fi
            if [[ `sysctl fs.suid_dumpable` != "fs.suid_dumpable = 0" ]]; then
                echo "fs.suid_dumpable = 0" >> /etc/sysctl.conf
            fi
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_1.6.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Enable Randomized Virtual Memory Region Placement (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ `sysctl kernel.randomize_va_space` == "kernel.randomize_va_space = 2" ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            util_set_configvalue /etc/sysctl.conf kernel.randomize_va_space 2
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}




function hard_2.1.01
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove telnet-server (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase telnet-server)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase telnet-server >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase telnet-server)
    printf "\n$fname:$check_status: $helpout"
}


function hard_2.1.02
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove telnet Clients (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase telnet)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase telnet >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase telnet)
    printf "\n$fname:$check_status: $helpout"
}


function hard_2.1.03
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove rsh-server (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase rsh-server)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase rsh-server >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase rsh-server)
    printf "\n$fname:$check_status: $helpout"
}


function hard_2.1.04
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove rsh (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase rsh)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase rsh >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase rsh)
    printf "\n$fname:$check_status: $helpout"
}


function hard_2.1.05
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove NIS Client (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase ypbind)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase ypbind >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase ypbind)
    printf "\n$fname:$check_status: $helpout"
}


function hard_2.1.06
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove NIS Server (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase ypserv)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase ypserv >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase ypserv)
    printf "\n$fname:$check_status: $helpout"
}


function hard_2.1.07
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove tftp (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase tftp)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase tftp >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase tftp)
    printf "\n$fname:$check_status: $helpout"
}



function hard_2.1.08
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove tftp-server (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase tftp-server)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase tftp-server >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase tftp-server)
    printf "\n$fname:$check_status: $helpout"
}



function hard_2.1.09
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove talk (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase talk)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase talk >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase talk)
    printf "\n$fname:$check_status: $helpout"
}



function hard_2.1.10
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove talk-server (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase talk-server)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase talk-server >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase talk-server)
    printf "\n$fname:$check_status: $helpout"
}


function hard_2.1.11
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove xinetd (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase xinetd)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase xinetd >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase xinetd)
    printf "\n$fname:$check_status: $helpout"
}


function hard_2.1.12
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable chargen-dgram (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_svcdisable chargen-dgram) 
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl disable chargen-dgram
        fi
    fi

    check_status=$(util_chk_svcdisable chargen-dgram) 
    printf "\n$fname:$check_status: $helpout"
}



function hard_2.1.13
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable chargen-stream (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_svcdisable chargen-stream)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl disable chargen-stream
        fi
    fi

    check_status=$(util_chk_svcdisable chargen-stream)
    printf "\n$fname:$check_status: $helpout"
}



function hard_2.1.14
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable daytime-dgram (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_svcdisable daytime-dgram)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl disable daytime-dgram
        fi
    fi

    check_status=$(util_chk_svcdisable daytime-dgram)
    printf "\n$fname:$check_status: $helpout"
}



function hard_2.1.15
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable daytime-stream (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_svcdisable daytime-stream)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl disable daytime-stream
        fi
    fi

    check_status=$(util_chk_svcdisable daytime-stream)
    printf "\n$fname:$check_status: $helpout"
}



function hard_2.1.16
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable echo-dgram (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_svcdisable echo-dgram)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl disable echo-dgram
        fi
    fi

    check_status=$(util_chk_svcdisable echo-dgram)
    printf "\n$fname:$check_status: $helpout"
}



function hard_2.1.17
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable echo-stream (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_svcdisable echo-stream)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl disable echo-stream
        fi
    fi

    check_status=$(util_chk_svcdisable echo-stream)
    printf "\n$fname:$check_status: $helpout"
}


function hard_2.1.18
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable tcpmux-server (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_svcdisable tcpmux-server)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl disable tcpmux-server
        fi
    fi

    check_status=$(util_chk_svcdisable tcpmux-server)
    printf "\n$fname:$check_status: $helpout"
}




function hard_3.01
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Set Daemon umask (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ `grep umask /etc/sysconfig/init` == "umask 027" ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sed -i '/^umask/d' /etc/sysconfig/init
            echo "umask 027" >> /etc/sysconfig/init
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_3.02
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove the X Window System (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ -z `ls -l /etc/systemd/system/default.target | grep graphical.target` ]] && [[ -z `rpm -q xorg-x11-server-common | grep ^xorg-x11-server-common` ]]; then 
                     echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            if [[ ! -z `ls -l /etc/systemd/system/default.target | grep graphical.target` ]]; then
                cd /etc/systemd/system
                unlink default.target
                ln -s /usr/lib/systemd/system/multi-user.target default.target
            fi 
            if [[ ! -z `rpm -q xorg-x11-server-common | grep ^xorg-x11-server-common` ]]; then
                yum -y remove xorg-x11-server-common >> $HARDEN_LOG
            fi
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_3.03
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable Avahi Server (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_svcdisable avahi-daemon)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl disable avahi-daemon
        fi
    fi

    check_status=$(util_chk_svcdisable avahi-daemon)
    printf "\n$fname:$check_status: $helpout"
}



function hard_3.04
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable Print Server - CUPS (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_svcdisable cups)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl disable cups
        fi
    fi

    check_status=$(util_chk_svcdisable cups)
    printf "\n$fname:$check_status: $helpout"
}


function hard_3.05
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove DHCP Server (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase dhcp)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase dhcp >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase dhcp)
    printf "\n$fname:$check_status: $helpout"
}



function hard_3.06
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Configure Network Time Protocol (NTP) (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi
    
    function check
    {
        if [[ ! -f /etc/ntp.conf ]]; then
            echo "NOT_OK"
            return
        elif [[ ! -z `grep "^restrict default" /etc/ntp.conf | grep kod | grep nomodify |grep notrap |grep nopeer |grep noquery` ]]  && \
             [[ ! -z `grep "^restrict -6 default" /etc/ntp.conf | grep kod | grep nomodify |grep notrap |grep nopeer |grep noquery` ]] && \
             [[ ! -z `grep ^server /etc/ntp.conf` ]] && \
             [[ ! -z `grep "^OPTIONS=" /etc/sysconfig/ntpd | grep ntp:ntp` ]]; then
            echo "OK" 
        else
            echo "NOT_OK"
        fi
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            if [[ ! -f /etc/ntp.conf ]]; then
                yum -y install ntp >> $HARDEN_LOG
            fi
            if [[ -z `grep "^restrict default" /etc/ntp.conf | grep kod | grep nomodify |grep notrap |grep nopeer |grep noquery` ]]; then
                sed -i 's/^restrict default.*/restrict default kod nomodify notrap nopeer noquery/' /etc/ntp.conf 
            fi
            if [[ -z `grep "^restrict -6 default" /etc/ntp.conf | grep kod | grep nomodify |grep notrap |grep nopeer |grep noquery` ]]; then
                if [[ ! -z `grep "^restrict -6 default" /etc/ntp.conf` ]]; then
                    sed -i 's/^restrict -6 default.*/restrict -6 default kod nomodify notrap nopeer noquery/' /etc/ntp.conf 
                else
                    echo "restrict -6 default kod nomodify notrap nopeer noquery" >> /etc/ntp.conf 
                fi
            fi
            if [[ -z `grep "^OPTIONS=" /etc/sysconfig/ntpd | grep ntp:ntp` ]]; then
                if [[ ! -z `grep "^OPTIONS=" /etc/sysconfig/ntpd | grep root:root` ]]; then
                    sed -i '/^OPTIONS=/s/root:root/ntp:ntp/g' /etc/sysconfig/ntpd 
                else
                    sed -i '/^OPTIONS=/s/\"/ -u ntp:ntp\"/2' /etc/sysconfig/ntpd
                fi
            fi
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}


function hard_3.07.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove LDAP Server (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase openldap-servers)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase openldap-servers >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase openldap-servers)
    printf "\n$fname:$check_status: $helpout"
}


function hard_3.07.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove LDAP Clients (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase openldap-clients)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase openldap-clients >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase openldap-clients)
    printf "\n$fname:$check_status: $helpout"
}



function hard_3.08
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable NFS & RPC (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ -z `systemctl list-unit-files | grep enabled | egrep "nfslock|rpcgssd|rpcbind|rpcidmapd|rpcsvcgssd"` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl disable nfslock
            systemctl disable rpcgssd
            systemctl disable rpcbind
            systemctl disable rpcidmapd
            systemctl disable rpcsvcgssd
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_3.09
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove DNS Server (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase bind)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase bind >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase bind)
    printf "\n$fname:$check_status: $helpout"
}



function hard_3.10
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove FTP Server (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase vsftpd)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase vsftpd >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase vsftpd)
    printf "\n$fname:$check_status: $helpout"
}


function hard_3.11
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove HTTP Server (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase httpd)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing: [enabled for smoke test]"
            #yum -y erase httpd >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase httpd)
    printf "\n$fname:$check_status: $helpout"
}



function hard_3.12
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove Dovecot (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase dovecot)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase dovecot >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase dovecot)
    printf "\n$fname:$check_status: $helpout"
}


function hard_3.13
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove Samba (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase samba)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase samba >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase samba)
    printf "\n$fname:$check_status: $helpout"
}



function hard_3.14
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove HTTP Proxy Server (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase squid)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase squid >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase squid)
    printf "\n$fname:$check_status: $helpout"
}



function hard_3.15
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Remove SNMP Server (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        check_status=$(util_chk_rpmerase net-snmp)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y erase net-snmp >> $HARDEN_LOG
        fi
    fi

    check_status=$(util_chk_rpmerase net-snmp)
    printf "\n$fname:$check_status: $helpout"
}



function hard_3.16
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Configure Mail Transfer Agent for Local-Only Mode (Scored)";
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ ! -z `netstat -an | grep LIST | grep ":25[[:space:]]" | grep -w ^tcp | grep 127.0.0.1` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sed -i '/^inet_interfaces/d' /etc/postfix/main.cf
            echo "inet_interfaces = localhost" >> /etc/postfix/main.cf
            systemctl restart postfix
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_4.1.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable IP Forwarding (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi
    
    declare -A sysArray=( [net.ipv4.ip_forward]=0 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}



function hard_4.1.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable Send Packet Redirects (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv4.conf.all.send_redirects]=0 [net.ipv4.conf.default.send_redirects]=0 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}



function hard_4.2.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable Source Routed Packet Acceptance (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv4.conf.all.accept_source_route]=0 [net.ipv4.conf.default.accept_source_route]=0 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}



function hard_4.2.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable ICMP Redirect Acceptance (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv4.conf.all.accept_redirects]=0 [net.ipv4.conf.default.accept_redirects]=0 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}



function hard_4.2.3
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable Secure ICMP Redirect Acceptance (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv4.conf.all.secure_redirects]=0 [net.ipv4.conf.default.secure_redirects]=0 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}


function hard_4.2.4
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Log Suspicious Packets (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv4.conf.all.log_martians]=1 [net.ipv4.conf.default.log_martians]=1 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}


function hard_4.2.5
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Enable Ignore Broadcast Requests (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv4.icmp_echo_ignore_broadcasts]=1 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}



function hard_4.2.6
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Enable Bad Error Message Protection (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv4.icmp_ignore_bogus_error_responses]=1 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}


function hard_4.2.7
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Enable RFC-recommended Source Route Validation (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv4.conf.all.rp_filter]=1 [net.ipv4.conf.default.rp_filter]=1 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}



function hard_4.2.8
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Enable TCP SYN Cookies (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv4.tcp_syncookies]=1 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}



function hard_4.4.1.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable IPv6 Router Advertisements (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv6.conf.all.accept_ra]=0 [net.ipv6.conf.default.accept_ra]=0 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
            /sbin/sysctl -w net.ipv6.route.flush=1 >> $HARDEN_LOG
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}


function hard_4.4.1.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable IPv6 Redirect Acceptance (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv6.conf.all.accept_redirects]=0 [net.ipv6.conf.default.accept_redirects]=0 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
            /sbin/sysctl -w net.ipv6.route.flush=1 >> $HARDEN_LOG
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}




function hard_4.4.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable IPv6 (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    declare -A sysArray=( [net.ipv6.conf.all.disable_ipv6]=1 )

    if [ "$cmd" == "fix" ]; then
        check_status=$(sysctl_match sysArray)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            sysctl_fix sysArray
            /sbin/sysctl -w net.ipv6.route.flush=1 >> $HARDEN_LOG
            sed -i "s/^inet_protocols =.*/inet_protocols = ipv4/" /etc/postfix/main.cf
            systemctl restart postfix >> $HARDEN_LOG
        fi
    fi

    check_status=$(sysctl_match sysArray)
    printf "\n$fname:$check_status: $helpout";
}


function hard_4.5.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Install TCP Wrappers (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ ! -z `rpm -q tcp_wrappers | grep ^tcp_wrappers` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y install tcp_wrappers >> $HARDEN_LOG
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_4.6
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    fslist="dccp sctp rds tipc"
    helpout="Disable Uncommon Network Protocols - $fslist"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi
    modfile=/etc/modprobe.d/CIS.conf

    function check
    {
        for fs in $fslist
        do
            if [[ -z `grep "install $fs /bin/true" $modfile` ]];  then
                echo "NOT_OK"
                return
            fi
        done
        echo "OK"
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            for fs in $fslist
            do
                if [[ -z `grep "install $fs /bin/true" $modfile` ]]; then
                    echo "install $fs /bin/true" >> $modfile
                fi
            done
        fi
    fi
    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}


function hard_4.7
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Enable firewalld (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ ! -z `systemctl list-unit-files | grep enabled | grep firewalld` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            if [[ -z `rpm -q firewalld | grep ^firewalld` ]]; then
                yum -y install firewalld >> $HARDEN_LOG
            fi 
            systemctl enable firewalld
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_5.1.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Install & Activate the rsyslog package (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ ! -z `systemctl list-unit-files | grep enabled | grep rsyslog` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            if [[ -z `rpm -q rsyslog | grep ^rsyslog` ]]; then
                yum -y install rsyslog >> $HARDEN_LOG
            fi
            systemctl enable rsyslog
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_5.1.4
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Create and Set Permissions on rsyslog Log Files (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi
    logfile_list=`grep /var/log /etc/rsyslog.conf | awk '{print $2}' | sed 's/^.*\/var/\/var/' | tr '\n' ' '`

    function check { 
        for lfile in $logfile_list
        do
            if [[ ! `stat -L -c "%a %u %g" $lfile` =~ "6"[4|0]"0 0 0" ]]; then
                echo "NOT_OK"
                return
            fi
        done
        echo "OK"
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            for lfile in $logfile_list
            do
                if [[ ! `stat -L -c "%a %u %g" $lfile` =~ "6"[4|0]"0 0 0" ]]; then
                    chown root:root $lfile
                    chmod g-wx,o-rwx $lfile
                fi
            done
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_5.2.1.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Configure Audit Log Storage Size (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        if [[ $(util_chk_configvalue /etc/audit/auditd.conf max_log_file TRUE) == 10 ]]; then check_status="OK"; else check_status="NOT_OK"; fi
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            util_set_configvalue /etc/audit/auditd.conf max_log_file 10 TRUE
        fi
    fi

    if [[ $(util_chk_configvalue /etc/audit/auditd.conf max_log_file TRUE) == 10 ]]; then check_status="OK"; else check_status="NOT_OK"; fi
    printf "\n$fname:$check_status: $helpout"
}
    


function hard_5.2.1.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable System on Audit Log Full (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi
    
    function check { if [[ $(util_chk_configvalue /etc/audit/auditd.conf space_left_action TRUE) == "email" ]] && \
                        [[ $(util_chk_configvalue /etc/audit/auditd.conf action_mail_acct TRUE) == "root" ]] && \
                        [[ $(util_chk_configvalue /etc/audit/auditd.conf admin_space_left_action TRUE) == "halt" ]]; then
                    echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            util_set_configvalue /etc/audit/auditd.conf space_left_action email TRUE
            util_set_configvalue /etc/audit/auditd.conf action_mail_acct root TRUE
            util_set_configvalue /etc/audit/auditd.conf admin_space_left_action halt TRUE
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_5.2.1.3
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Keep All Auditing Information (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    if [ "$cmd" == "fix" ]; then
        if [[ $(util_chk_configvalue /etc/audit/auditd.conf max_log_file_action TRUE) == "keep_logs" ]]; then check_status="OK"; else check_status="NOT_OK"; fi
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            util_set_configvalue /etc/audit/auditd.conf max_log_file_action keep_logs TRUE
        fi
    fi

    if [[ $(util_chk_configvalue /etc/audit/auditd.conf max_log_file_action TRUE) == "keep_logs" ]]; then check_status="OK"; else check_status="NOT_OK"; fi
    printf "\n$fname:$check_status: $helpout"
}



function hard_5.2.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Enable auditd Service (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ ! -z `systemctl list-unit-files | grep enabled | grep auditd` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl enable auditd
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_5.2.3
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Enable Auditing for Processes That Start Prior to auditd (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { 
        lines=`grep "^[[:space:]].*linux" /boot/grub2/grub.cfg | wc -l`
        lines_audit=`grep "^[[:space:]].*linux" /boot/grub2/grub.cfg | grep "audit=1" | wc -l`
        if [[ $lines == $lines_audit ]]; then echo "OK"; else echo "NOT_OK"; fi
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            if [[ -z `grep "^GRUB_CMDLINE_LINUX=" /etc/default/grub | grep "audit=1"` ]]; then
                sed -i '/^GRUB_CMDLINE_LINUX=/s/\"/,audit=1\"/2' /etc/default/grub
            fi
            grub2-mkconfig -o /boot/grub2/grub.cfg >> $HARDEN_LOG
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_5.3
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Configure logrotate (Not Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi
    file_list="/var/log/messages /var/log/secure /var/log/maillog /var/log/spooler /var/log/boot.log /var/log/cron"
    grep_file_list="/var/log/messages|/var/log/secure|/var/log/maillog|/var/log/spooler|/var/log/boot.log|/var/log/cron"

    function check { if [[ `egrep "$grep_file_list" /etc/logrotate.d/syslog | wc -l` == 6 ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            for f in $file_list
            do
                if [[ -z `grep $f /etc/logrotate.d/syslog` ]]; then
                    sed -i "1i $f" /etc/logrotate.d/syslog
                fi
            done
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_6.1.01
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Enable anacron Daemon (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ ! -z `rpm -q cronie-anacron | grep ^cronie-anacron` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            yum -y install cronie-anacron >> $HARDEN_LOG
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_6.1.02
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Enable crond Daemon (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ ! -z `systemctl list-unit-files | grep enabled | grep crond` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            systemctl enable crond
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}




function hard_6.1.03
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    fs_list="/etc/anacrontab /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d"
    helpout="Set User/Group Owner and Permission on $fs_list (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check {
        for lfile in $fs_list
        do
            if [[ -z `stat -L -c "%a %u %g" $lfile | egrep ".00 0 0"` ]]; then
                echo "NOT_OK"
                return
            fi
        done
        echo "OK"
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            for lfile in $fs_list
            do
                if [[ -z `stat -L -c "%a %u %g" $lfile | egrep ".00 0 0"` ]]; then
                    chown root:root $lfile
                    chmod og-rwx $lfile
                fi
            done
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_6.1.10
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Restrict at/cron (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check {
        for lfile in /etc/cron.allow /etc/at.allow
        do
            if [[ ! -f $lfile ]] || [[ -z `stat -L -c "%a %u %g" $lfile | egrep ".00 0 0"` ]]; then
                echo "NOT_OK"
                return
            fi
        done
        for lfile in /etc/cron.deny /etc/at.deny
        do
            if [[ -f $lfile ]]; then
                echo "NOT_OK"
                return
            fi
        done
        echo "OK"
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            rm -f /etc/cron.deny /etc/at.deny
            for lfile in /etc/cron.allow /etc/at.allow
            do
                if [[ ! -f $lfile ]]; then touch $lfile; fi
                chmod og-rwx $lfile
                chown root:root $lfile  
            done 
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_6.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Configure sshd_config (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check {
        if [[ $(util_chk_configvalue_nodelimeter /etc/ssh/sshd_config Protocol) != 2 ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/ssh/sshd_config LogLevel) != "INFO" ]] || \
           [[ -z `stat -L -c "%a %u %g" /etc/ssh/sshd_config | egrep ".00 0 0"` ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/ssh/sshd_config X11Forwarding) != "no" ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/ssh/sshd_config MaxAuthTries) != 4 ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/ssh/sshd_config IgnoreRhosts) != "yes" ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/ssh/sshd_config HostbasedAuthentication) != "no" ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/ssh/sshd_config PermitRootLogin) != "no" ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/ssh/sshd_config PermitEmptyPasswords) != "no" ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/ssh/sshd_config PermitUserEnvironment) != "no" ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/ssh/sshd_config Ciphers) != "aes128-ctr,aes192-ctr,aes256-ctr" ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/ssh/sshd_config Banner) != "/etc/issue.net" ]]; then
        echo "NOT_OK"
        else echo "OK"
        fi  
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            util_set_configvalue_nodelimeter /etc/ssh/sshd_config Protocol 2
            util_set_configvalue_nodelimeter /etc/ssh/sshd_config LogLevel INFO
            util_set_configvalue_nodelimeter /etc/ssh/sshd_config X11Forwarding no
            util_set_configvalue_nodelimeter /etc/ssh/sshd_config MaxAuthTries 4
            util_set_configvalue_nodelimeter /etc/ssh/sshd_config IgnoreRhosts yes
            util_set_configvalue_nodelimeter /etc/ssh/sshd_config HostbasedAuthentication no
            util_set_configvalue_nodelimeter /etc/ssh/sshd_config PermitRootLogin no
            util_set_configvalue_nodelimeter /etc/ssh/sshd_config PermitEmptyPasswords no
            util_set_configvalue_nodelimeter /etc/ssh/sshd_config PermitUserEnvironment no
            util_set_configvalue_nodelimeter /etc/ssh/sshd_config Ciphers aes128-ctr,aes192-ctr,aes256-ctr
            util_set_configvalue_nodelimeter /etc/ssh/sshd_config Banner /etc/issue.net
            chown root:root /etc/ssh/sshd_config
            chmod 600 /etc/ssh/sshd_config            
        fi
    fi
   
    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_6.3.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Upgrade Password Hashing Algorithm to SHA-512 (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ ! -z `authconfig --test | grep hashing | grep sha512` ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            authconfig --passalgo=sha512 --update
            cat /etc/passwd | awk -F: '( $3 >=1000 && $1 != "nfsnobody" ) { print $1 }' | xargs -n 1 chage -d 0
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}


function hard_6.3.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Set Password Creation Requirement Parameters Using pam_pwquality (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ ! -z `grep pam_pwquality.so /etc/pam.d/system-auth | grep  try_first_pass | grep local_users_only | grep retry=3 | grep authtok_type=` ]] && \
                        [[ $(util_chk_configvalue /etc/security/pwquality.conf minlen TRUE) == "14" ]] && \
                        [[ $(util_chk_configvalue /etc/security/pwquality.conf dcredit TRUE) == "-1" ]] && \
                        [[ $(util_chk_configvalue /etc/security/pwquality.conf ucredit TRUE) == "-1" ]] && \
                        [[ $(util_chk_configvalue /etc/security/pwquality.conf ocredit TRUE) == "-1" ]] && \
                        [[ $(util_chk_configvalue /etc/security/pwquality.conf lcredit TRUE) == "-1" ]]; then
                        echo "OK";
                    else echo "NOT_OK";
                    fi
                   }


    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            if [[ -z `grep pam_pwquality.so /etc/pam.d/system-auth | grep  try_first_pass | grep local_users_only | grep retry=3 | grep authtok_type=` ]]; then
                sed -i 's/^.*pam_pwquality.so.*$/password\trequisite\tpam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=/g' /etc/pam.d/system-auth                 
            fi
            if [[ $(util_chk_configvalue /etc/security/pwquality.conf minlen TRUE) != 14 ]]; then util_set_configvalue /etc/security/pwquality.conf minlen 14 TRUE; fi
            if [[ $(util_chk_configvalue /etc/security/pwquality.conf dcredit TRUE) != "-1" ]]; then util_set_configvalue /etc/security/pwquality.conf dcredit "-1" TRUE; fi
            if [[ $(util_chk_configvalue /etc/security/pwquality.conf ucredit TRUE) != "-1" ]]; then util_set_configvalue /etc/security/pwquality.conf ucredit "-1" TRUE; fi
            if [[ $(util_chk_configvalue /etc/security/pwquality.conf ocredit TRUE) != "-1" ]]; then util_set_configvalue /etc/security/pwquality.conf ocredit "-1" TRUE; fi
            if [[ $(util_chk_configvalue /etc/security/pwquality.conf lcredit TRUE) != "-1" ]]; then util_set_configvalue /etc/security/pwquality.conf lcredit "-1" TRUE; fi


        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_7.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Set Shadow Password Suite Parameters (/etc/login.defs) (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check {
        if [[ $(util_chk_configvalue_nodelimeter /etc/login.defs PASS_MAX_DAYS) != 90 ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/login.defs PASS_MIN_DAYS) != 7 ]] || \
           [[ $(util_chk_configvalue_nodelimeter /etc/login.defs PASS_WARN_AGE) != 7 ]]; then
        echo "NOT_OK"
        else echo "OK"
        fi  
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            util_set_configvalue_nodelimeter /etc/login.defs PASS_MAX_DAYS 90
            util_set_configvalue_nodelimeter /etc/login.defs PASS_MIN_DAYS 7
            util_set_configvalue_nodelimeter /etc/login.defs PASS_WARN_AGE 7
        fi
    fi
   
    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}


function hard_7.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Disable System Accounts (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ -z `egrep -v "^\+" /etc/passwd | awk -F: '($1!="root" && $1!="sync" && $1!="shutdown" && $1!="halt" && $3<1000 && $7!="/sbin/nologin") {print}'` ]]; then 
                          echo "OK"
                     else 
                          echo "NOT_OK"
                     fi  
                   }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"

            for user in `awk -F: '($3 < 1000) {print $1 }' /etc/passwd`; 
            do
                if [[ $user != "root" ]]; then
                    /usr/sbin/usermod -L $user
                    if [ $user != "sync" ] && [ $user != "shutdown" ] && [ $user != "halt" ]; then
                        /usr/sbin/usermod -s /sbin/nologin $user
                    fi
                fi
            done            
        fi
    fi
   
    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}


function hard_7.3 
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Set Default Group for root Account (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ `grep "^root:" /etc/passwd | cut -f4 -d:` == 0 ]]; then echo "OK"; else echo "NOT_OK"; fi } 

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            usermod -g 0 root
        fi
    fi
   
    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_7.4
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    fs_list="/etc/profile /etc/bashrc /root/.bashrc /root/.bash_profile"
    helpout="Set Default umask for Users (Scored) $fs_list /etc/login.defs"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { 

        for fs in $fs_list 
        do
            if [[ $(util_chk_configvalue_nodelimeter $fs umask) != "077" ]]; then
                echo "NOT_OK"
                return
            fi
        done
        if [[ $(util_chk_configvalue_nodelimeter /etc/login.defs UMASK) != "077" ]]; then
            echo "NOT_OK"
            return
        fi
        echo "OK"
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            for fs in $fs_list
            do
                if [[ $(util_chk_configvalue_nodelimeter $fs umask) != "077" ]]; then
                    util_set_configvalue_nodelimeter $fs umask 077
                fi
            done
            if [[ $(util_chk_configvalue_nodelimeter /etc/login.defs UMASK) != "077" ]]; then
                util_set_configvalue_nodelimeter /etc/login.defs UMASK 077
            fi
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_7.5
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Lock Inactive User Accounts (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ `useradd -D | grep INACTIVE | gawk -F\= '{print $2}'` < 35 ]]; then echo "NOT_OK"; else echo "OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            useradd -D -f 35
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_8.1
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Set Warning Banner for Standard Login Services (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi
    msg="Authorized uses only. All activity may be monitored and reported."

    function check { 
        if [[ `stat -L -c "%a %u %g %s" /etc/motd` =~ "6"[4|0][4|0]" 0 0 0" ]] && \
           [[ `stat -L -c "%a %u %g" /etc/issue` =~ "6"[4|0][4|0]" 0 0" ]] && \
           [[ `stat -L -c "%a %u %g" /etc/issue.net` =~ "6"[4|0][4|0]" 0 0" ]] && \
           [[ -f /etc/motd ]] && \
           [[ `cat /etc/issue` == "$msg" ]] && \
           [[ `cat /etc/issue.net` == "$msg" ]]; then
           echo "OK"
        else
            echo "NOT_OK"
        fi 

    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            chown root:root /etc/motd /etc/issue /etc/issue.net
            chmod 644 /etc/motd /etc/issue /etc/issue.net
            cp /dev/null /etc/motd
            echo $msg > /etc/issue
            echo $msg > /etc/issue.net
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_9.1.2
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Verify Permissions & Ownership on /etc/passwd /etc/shadow /etc/gshadow /etc/group (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { 
        if [[ `stat -L -c "%a %u %g" /etc/passwd` =~ "6"[4|0][4|0]" 0 0" ]] && \
           [[ `stat -L -c "%a %u %g" /etc/shadow` = "0 0 0" ]] && \
           [[ `stat -L -c "%a %u %g" /etc/gshadow` = "0 0 0" ]] && \
           [[ `stat -L -c "%a %u %g" /etc/group` =~ "6"[4|0][4|0]" 0 0" ]]; then
           echo "OK"
        else
            echo "NOT_OK"
        fi 
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            chown root:root /etc/passwd /etc/shadow /etc/gshadow /etc/group
            chmod 644 /etc/passwd /etc/group
            chmod 000 /etc/shadow /etc/gshadow
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}


function hard_9.2.01
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Ensure Password Fields are Not Empty (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { 
        if [[ -z `cat /etc/shadow | gawk -F: '($2 == "" ) { print $1 }'` ]]; then
           echo "OK"
        else
           echo "NOT_OK"
        fi 
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            for puser in `cat /etc/shadow | gawk -F: '($2 == "" ) { print $1 }'`
            do
                passwd -l $puser
            done
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}



function hard_9.2.02
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Verify No Legacy '+' Entries Exist in /etc/passwd /etc/shadow /etc/group Files (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { 
        if [[ -z `grep "^+:" /etc/passwd` ]] && \
           [[ -z `grep "^+:" /etc/shadow` ]] && \
           [[ -z `grep "^+:" /etc/group` ]]; then
           echo "OK"
        else
           echo "NOT_OK"
        fi 
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname: Fixing"
            for fs in /etc/passwd /etc/shadow /etc/group
            do
                if [[ ! -z `grep "^+:" $fs` ]]; then sed -i '/^+:/d' $fs; fi
            done
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}


function hard_9.2.05
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Verify No UID 0 Accounts Exist Other Than root (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi

    function check { if [[ `cat /etc/passwd | /bin/awk -F: '($3 == 0) { print $1 }'` == "root" ]]; then echo "OK"; else echo "NOT_OK"; fi }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname:UserFix:Multiple users with 0 UID in /etc/passwd: "
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}




function hard_9.2.06
{
    cmd=$1
    fname=`echo $FUNCNAME | sed 's/hard_//'`
    helpout="Ensure root PATH Integrity (Scored)"
    if [ "$cmd" == "help" ]; then
        printf "\n$fname: $helpout"
        return
    fi
    
    function check {
        if [[ ! -z `echo $PATH | grep "::"` ]] || [[ ! -z `echo $PATH | grep ":$"` ]]; then
            echo "NOT_OK"
            return
        fi
        NEWPATH=`echo $PATH | sed -e 's/::/:/g' -e 's/:$//' -e 's/:/ /g'`
        set -- $NEWPATH 
        while [[ $1 != "" ]]; 
        do
            if [[ ! -d $1 ]]; then
                echo "NOT_OK"
                return 
            fi
            if [[ ! `stat -L -c "%a %u %g" $1` =~ [0|2|5][0|2|5]" 0 0" ]]; then 
                echo "NOT_OK"
                return
            fi
            shift
        done
        echo "OK"
    }

    if [ "$cmd" == "fix" ]; then
        check_status=$(check)
        if [ "$check_status" == "NOT_OK" ]; then
            printf "\n$fname:UserFix:"
            if [[ ! -z `echo $PATH | grep "::"` ]] || [[ ! -z `echo $PATH | grep ":$"` ]]; then
                printf "\nRoot PATH contains :: or ends with :" 
            fi
            NEWPATH=`echo $PATH | sed -e 's/::/:/g' -e 's/:$//' -e 's/:/ /g'`
            set -- $NEWPATH
            while [[ $1 != "" ]];
            do
                if [[ ! -d $1 ]]; then printf "\n$fname:UserFix:$1:Missing directory"; shift; continue; fi
                if [[ ! `stat -L -c "%a %u %g" $1` =~ [0|2|5][0|2|5]" 0 0" ]]; then printf "\n$fname:UserFix:$1:Permissions incorrect"; fi
                shift
            done
        fi
    fi

    check_status=$(check)
    printf "\n$fname:$check_status: $helpout"
}







function run_harden 
{
    cmd=$1
    printf "\nrun_harden: $cmd"
    shift
    
    if [ "$cmd" == "help" ] || [ "$1" == "all" ]; then
        funclist=`compgen -A function|grep ^hard | cut -c6-`
    else
        funclist=$@
    fi
    echo
    echo "Functions:" $funclist

    touch $HARDEN_OUTPUT 
    printf "\n--------- Begin ----------"
    for func in $funclist
    do
        func_name=hard_${func}
        $func_name $cmd | tee -a $HARDEN_OUTPUT
    done
    printf "\n--------- End ----------"
    echo

    printf "\n\n*** Summary ***\n"
    egrep "UserFix|NOT_OK" $HARDEN_OUTPUT | sort
    echo
}

clear
printf "\nOS Hardening running on `cat /etc/redhat-release`"

configfile="harden.cfg"
source $configfile
printf "\n----- Config -----"
printf "\ntmp_mntpt = $tmp_mntpt"
printf "\nvar_mntpt = $var_mntpt"
printf "\nvarlog_mntpt = $varlog_mntpt"
printf "\nhome_mntpt = $home_mntpt"
printf "\n\n"

for vg in $tmp_mntpt $var_mntpt $varlog_mntpt $home_mntpt
do 
    if [[ ! -z `lvdisplay $vg | grep "LV Path"` ]]; then 
        vgsize=`lvdisplay $vg | grep "LV Size" | gawk '{print $3$4}'`
    printf "\n$vg: LV Created ($vgsize)"
    fi
done
echo

while getopts :c:f:h FLAG; do
  case $FLAG in
    c)  
      check_list=$OPTARG
      run_harden check $check_list
      ;;
    f) 
      fix_list=$OPTARG
      run_harden fix $fix_list
      ;;
    h)
      run_harden help $help_list
      ;;
    z)  #show help
      HELP
      ;;
    \?) 
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      echo -e "Use ${BOLD}$SCRIPT -h${NORM} to see the help documentation."\\n
      exit 2
      ;;
  esac
done


