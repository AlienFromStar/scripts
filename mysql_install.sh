#!/bin/sh

<<COMMENT
   FILE: mysql_install.sh
   USAGE: mysql_install.sh 3306
   AUTHOR: fanmeng
   CREATED: 2019.04.14
   VERSION: 1.0
   MYSQL version：5.7.25
   CENTOS 7.5 X64
COMMENT

#setting eg PORT
if [ -z $1];then
   PORT=3306
else
   PORT=$1
fi

#soft tar is in current dir 
SOFTDIR="$( cd "$( dirname "$0"  )" && pwd  )"

#don't have ".tar.gz"!!!
tarbag="mysql-5.7.25-linux-glibc2.12-x86_64"
BASEDIR="/usr/local/mysql"
DATADIR="/data/mysql"

##bc install
yum install -q -y bc

CPU_NUMBERS=$(cat /proc/cpuinfo |grep "processor"|wc -l)
MYSQL_SERVER_ID=`ip a | egrep "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | grep -v "127.0.0.1" | awk -F. '{print $4}' | awk -F/ '{print $1}' | head -1`
COMPUTER_MEM=`free -m |grep "Mem"|awk '{print $2}'`
INNODB_BUFFER_SIZE=`bc <<< $COMPUTER_MEM*0.7/1`
HOST_NAME=`hostname`

#check if user is root
if [ $(id -u) != "0" ];then
   echo "Error: You must be root to run this script!"
   exit 1
fi

  
#remove before being installed mysql
function rmMysql() {
        rpm -qa | egrep -i "mysql|mariadb" | xargs rpm -e --nodeps >/dev/null 2>&1
        num=`rpm -qa | grep -i mysql | wc -l`
        test $num -gt 1 &&  echo "mysql-server or mariadb uninstall failed" && exit 1
}
#libaio package is needed for mysql5.7
function chkEnv() {
        #install libaio
        yum -y -q install libaio >/dev/null 2>&1
        res=`rpm -aq|grep libaio | wc -l`
        test $res -ne 1 && echo "libaio package install failed..." && exit 2
		
		#add env ,add mysql bin
        echo -e "adding mysql bin to env PATH..."
		sed -i "s|^PATH.*$|&:${BASEDIR}/bin|g" /root/.bash_profile
        source /root/.bash_profile
}
  
#add user and group
function addMysqlUser(){
        #add group
		if [ -z $(cat /etc/group|awk -F: '{print $1}'| grep -w "mysql") ]
		then
		    groupadd  mysql
			if(( $? == 0 ))
			  then
				 echo "group mysql add sucessfully!"
			fi
		else
		  echo "os usergroup mysql is exsits"
		fi
		
		#add user
		if [ -z $(cat /etc/passwd|awk -F: '{print $1}'| grep -w "mysql") ]
		then
		     useradd -r -g mysql -s /bin/false mysql
			 if (( $? == 0 ))
			   then
			   echo "user mysql add sucessfully!"
			 fi
		else
		  echo "os user mysql is exsits"
		fi		
}  
  
#authorization, extract
function preInstall() {
        mkdir -p $DATADIR
        chown -R mysql.mysql $DATADIR
        if test -f $SOFTDIR/$tarbag.tar.gz
          then
                cd $SOFTDIR && tar -zxvf $tarbag.tar.gz
				[ $? -ne 0 ] && echo "tar -zxvf $tarbag.tar.gz failed!!" && exit 10
				[ -d $BASEDIR ] && mv $BASEDIR  ${BASEDIR}_old
                mv $SOFTDIR/$tarbag $BASEDIR
          else
                echo "$tarbag.tar.gz is not found..."
                exit 10
        fi
}
  


function install_mysql() {
        #initialize mysql database
        $BASEDIR/bin/mysqld --defaults-file=/etc/my.cnf --initialize-insecure
}



#config /etc/my.cnf mysql cnf
function mysql_cnf_config() {
		#backup old my.cnf 
		if [ -s /etc/my.cnf ]; then
			mv /etc/my.cnf /etc/my.cnf.`date +%Y%m%d%H%M%S`.bak
		fi
		
		#disk is hdd or ssd?
		ishdd=`cat /sys/block/sda/queue/rotational`
		innodb_flush_neighbors=""
		innodb_io_capacity=""
		innodb_io_capacity_max=""
		if [ $ishdd -eq 0 ];then
		   innodb_flush_neighbors=0
		   innodb_io_capacity=10000
		   innodb_io_capacity_max=20000
		else
		   innodb_flush_neighbors=1
		   innodb_io_capacity=500
		   innodb_io_capacity_max=1000			
		fi
		
		
		#config
		cat >>/etc/my.cnf<<EOF
[client]
port = ${PORT}
socket = $DATADIR/mysql.sock
prompt = [\\u@\\h][\\d]>\\_


[mysqld]
#==basic settings======#
user = mysql
server-id = ${MYSQL_SERVER_ID}
port = ${PORT}
sql_mode = "STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER"
autocommit = 1
character_set_server=utf8mb4
transaction_isolation = READ-COMMITTED
explicit_defaults_for_timestamp = 1
max_allowed_packet = 16777216
event_scheduler = 1
lower_case_table_names = 1
basedir = $BASEDIR
datadir = $DATADIR
tmpdir  = /tmp
socket  = $DATADIR/mysql.sock

#==connection======#
interactive_timeout = 1800
wait_timeout = 1800
lock_wait_timeout = 1800
skip_name_resolve = 1
max_connections = 1000
max_connect_errors = 1000000
back_log = 130


#==table cache performance settings======#
table_open_cache = 4096
table_definition_cache = 4096
#table_open_cache_instances = 128

#==session memory settings======#
read_buffer_size = 16M
read_rnd_buffer_size = 32M
sort_buffer_size = 32M
tmp_table_size = 64M
join_buffer_size = 128M
thread_cache_size = 64

#==log settings======#
log_error = error.log
log-bin=binlog_${HOST_NAME}
slow_query_log = 1
slow_query_log_file = slow.log
log_queries_not_using_indexes = 1
log_slow_admin_statements = 1
log_slow_slave_statements = 1
log_throttle_queries_not_using_indexes = 10
binlog_cache_size = 524288
expire_logs_days = 30
long_query_time = 2
min_examined_row_limit = 100
binlog-rows-query-log-events = 1
log-bin-trust-function-creators = 1
expire-logs-days = 90
log-slave-updates = 1


#==new innodb settings======#
#innodb_page_cleaners = 16
#innodb_write_io_threads = 16
#innodb_read_io_threads = 16
#innodb_purge_threads = 4
innodb_purge_rseg_truncate_frequency = 128

#==innodb settings======#
innodb_buffer_pool_size = ${INNODB_BUFFER_SIZE}m
innodb_buffer_pool_instances = 16
innodb_buffer_pool_load_at_startup = 1
innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_dump_pct = 40
innodb_lru_scan_depth = 4096
innodb_lock_wait_timeout = 5
innodb_io_capacity = $innodb_io_capacity
innodb_io_capacity_max = $innodb_io_capacity_max
innodb_flush_method = O_DIRECT
 
##default 1, if disk is ssd, need off
innodb_flush_neighbors=$innodb_flush_neighbors
 
innodb_log_buffer_size = 16777216
innodb_large_prefix = 1
innodb_thread_concurrency = 64
innodb_print_all_deadlocks = 1
innodb_strict_mode = 1
innodb_sort_buffer_size = 67108864

innodb_file_per_table = 1
innodb_stats_persistent_sample_pages = 64
innodb_autoinc_lock_mode = 2
innodb_online_alter_log_max_size=1G
innodb_open_files=4096

###redo，undo
innodb_undo_logs = 128
innodb_undo_tablespaces = 3
innodb_undo_log_truncate = 1
innodb_max_undo_log_size = 2G
innodb_log_files_in_group = 3
innodb_log_file_size = 1024m

#==replication settings======#
master_info_repository = TABLE
relay_log_info_repository = TABLE
sync_binlog = 1
gtid_mode = on
enforce_gtid_consistency = 1
log_slave_updates
binlog_format = ROW
binlog_row_image = full
binlog_rows_query_log_events = 1
relay_log = relay.log
relay_log_recovery = 1
slave_skip_errors = ddl_exist_errors
slave-rows-search-algorithms = 'INDEX_SCAN,HASH_SCAN'

#==semi sync replication settings #
plugin_load = "rpl_semi_sync_master=semisync_master.so;rpl_semi_sync_slave=semisync_slave.so"
rpl_semi_sync_master_enabled = 1
rpl_semi_sync_master_timeout = 3000
rpl_semi_sync_slave_enabled = 1

#==password plugin======#
#validate_password_policy=STRONG
#validate-password=FORCE_PLUS_PERMANENT

 
 


#==new replication settings======#
slave-parallel-type = LOGICAL_CLOCK
slave-parallel-workers = 8
slave_preserve_commit_order=1
slave_transaction_retries=128

# other change settings #
binlog_gtid_simple_recovery=1
log_timestamps=system
show_compatibility_56=on
EOF
}


#add service on centos 6
function add_mysql_service_c6() {
        #add server 
        cp $SOFTDIR/$tarbag/support-files/mysql.server /etc/init.d/mysqld
        chmod a+x /etc/init.d/mysqld
        chkconfig --add mysqld 
		chkconfig --level 35 mysqld on
		
		#startup mysql
        service mysqld start
		
		#check mysql status
        sleep 3
        psnum=`netstat -natp|grep mysqld | grep "$1" | wc -l`
		if [ $psnum -eq 1 ];then
			echo -e "\033[33;1mmysql install success...\033[0m"
		else
			echo -e "\033[31;1mmysql start failed, please check...\033[0m"
			exit 1
        fi		
}

#add systemctl on centos 7
function add_mysql_service_c7() {
        #add server 
        touch /usr/lib/systemd/system/mysqld.service
	cat >/usr/lib/systemd/system/mysqld.service<<EOF
[Unit]
Description=MySQL Server
Documentation=man:mysqld(8)
Documentation=http://dev.mysql.com/doc/refman/en/using-systemd.html
After=network.target
After=syslog.target

[Install]
WantedBy=multi-user.target

[Service]
User=mysql
Group=mysql
Type=forking

# Disable service start and stop timeout logic of systemd for mysqld service.
TimeoutSec=0

# Execute pre and post scripts as root
PermissionsStartOnly=true

PIDFile=$DATADIR/mysqld.pid 
ExecStart=${BASEDIR}/bin/mysqld   --defaults-file=/etc/my.cnf  --daemonize --pid-file=$DATADIR/mysqld.pid  
Restart=on-failure 
RestartPreventExitStatus=1 
PrivateTmp=false
LimitNOFILE=65535
EOF

		#startup mysql
		systemctl enable mysqld.service
        systemctl start mysqld 
		
		#check mysql status
        sleep 3
        psnum=`netstat -natp|grep mysqld | grep "$1" | wc -l`
		if [ $psnum -eq 1 ];then
			echo -e "\033[33;1mmysql install success...\033[0m"
		else
			echo -e "\033[31;1mmysql start failed, please check...\033[0m"
			exit 1
        fi		
}


exist_PORT_num=`netstat -natp | grep "mysqld" | grep "LISTEN" | grep ":$PORT" | wc -l `
if [[ $exist_PORT_num == 1 ]] ; then
   echo -e "\033[33;1m$1 mysql instance (PORT is ${PORT}) has already existed...\033[0m"
   exit 1
else
   echo -e "\033[32;1mStarting create new instance $1\033[0m"
   echo -e "\033[32;1m 1.check and rm exists mysql service $1\033[0m"
   rmMysql
   echo -e "\033[32;1m 2.install libaio package and add mysql bin to PATH ENV... $1\033[0m"
   chkEnv
   echo -e "\033[32;1m 3.add mysql user and usergroup... $1\033[0m"
   addMysqlUser
   echo -e "\033[32;1m 4.mkdir mysql data folder and extract tarball... \033[0m"
   preInstall
   echo -e "\033[32;1m 5.config mysql to /etc/my.cnf... $1\033[0m"
   mysql_cnf_config
   echo -e "\033[32;1m 6.install mysql,init data... $1\033[0m"
   install_mysql
   echo -e "\033[32;1m 6.add and config mysql service... $1\033[0m"
   ##centos6 or centos7
   isc7=`cat /etc/redhat-release | grep "CentOS Linux release 7." | wc -l`
   if [ $isc7 = 1 ];then
      echo "system os is centos 7"
      add_mysql_service_c7
   else
      echo "system os is centos 6"
      add_mysql_service_c6
   fi
   
   source /root/.bash_profile
fi
