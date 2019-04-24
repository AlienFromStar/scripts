#!/bin/sh

#测试逻辑，从并发1个文件到最大数量文件下的每个不同文件读写测试模式压力测试，获取对应的请求数和吞吐量数据

#配置参数
BASEDIR="/data/sysbench/`date "+%Y-%m-%d"`"
FILE_TOTAL_SIZE=32G
RESULT_REPORT=${BASEDIR}/report.txt

#测试的写入方式
	#seqwr 顺序写入
	#seqrewr 顺序重写
	#seqrd 顺序读取
	#rndrd 随机读取
	#rndwr 随机写入
	#rndrw 混合随机读/写
TEST_MODE="seqwr seqrewr seqrd rndrd rndwr rndrw"



#创建及清理准备工作
if [ ! -d $BASEDIR ]
then
   mkdir $BASEDIR -p
else
   mv $BASEDIR  ${BASEDIR}_OLD
   mkdir $BASEDIR -p
fi

cd $BASEDIR


# 记录所有错误及标准输出到 sysbench.log 中
#exec 3>&1 4>&2 1>> sysbench.log 2>&1





function fun_flush_wait
{
        echo "开始flush_wait..."
        #刷新脏数据
	sync
	#清除cache
	echo 3 >/proc/sys/vm/drop_caches
	#释放swap
	swapoff -a && swapon -a			
	sleep 10
}


function fun_sysbench
{
	thread=$1
	testmode=$2
	logfile=${BASEDIR}/log_${thread}_${testmode}.log
        echo "开始prepare文件..."
        rm $BASEDIR/test_file.* -f
        sysbench --test=fileio --file-total-size=${FILE_TOTAL_SIZE}  prepare
        
        fun_flush_wait
        
        echo "接下来将开始run:thread:${thread}, testmode:=${testmode}"
	sysbench  --test=fileio --threads=${thread} --file-total-size=${FILE_TOTAL_SIZE} --file-test-mode=${testmode} --file-rw-ratio=4  run | tee -a ${logfile}
	
	#获取结果值IOPS
	iops=`egrep "reads/s|writes/s|fsyncs/s" ${logfile}  |  awk '{sum += $2} END {print sum}' `
	
	#获取吞吐量
	throughput=`egrep "MiB/s" ${logfile}  |  awk '{sum += $3} END {print sum}'`
	
	#获取平均响应时间
	avg_Latency=`egrep "avg:" ${logfile}  |  awk '{print $2}'`
	
	echo "${testmode} ${thread}  ${iops}  ${throughput}  ${avg_Latency}" >> ${RESULT_REPORT}
   
}



echo "开始run..."

#测试线程数，从2到40，递增2
for (( i=1; i<=40; i=i+2 ))
do
	for testmode in `echo "${TEST_MODE}"`
	do
		fun_sysbench  ${i} ${testmode} 
		fun_flush_wait		
	done
done
