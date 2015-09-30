#!/usr/bin/env bash



# client_ip.sh [OPTION]... [FILE]...

# 参数列表
#   -t      type, 日志文件类型，供选值 iis, apache
#   -s      separate 字段分隔符 av_FS
#   -p      pattern, 字段模式 av_FPAT
#   -f      field, 字段编号位置 av_FIELD_INDEX
#   -d      debug, 输出调试信息 dbg

dbg=0
#echo "init OPTIND:" $OPTIND
while getopts "t:s:p:f:d" arg
do
    case $arg in
        t)
            av_LOGTYPE=$OPTARG
            ;;
        s)
            av_FS=$OPTARG
            ;;
        p)
            av_FPAT=$OPTARG
            ;;
        f)
            av_FIELD_INDEX=$OPTARG
            ;;
        d)
            dbg=1
            ;;
        ?)
    esac
done

LOGTYPE=$av_LOGTYPE

if [ "${dbg}" == "1" ]; then
    echo "---- debug ---------"
    echo "av_LOGTYPE:        ["$av_LOGTYPE"]"
    echo "av_FS:             ["$av_FS"]"
    echo "av_FPAT:           ["$av_FPAT"]"
    echo "av_FIELD_INDEX:    ["$av_FIELD_INDEX"]"
    echo "---- debug done ---------"
fi


#if [ "${av_FS}" == "  " ]; then
#    echo 'av_FS is blank'
#else
#    echo "av_FS not"
#fi


shift $((OPTIND-1))

#for file in $@
#do
#    echo "file: " $file
#done

if [ -n "${av_LOGTYPE}" ]; then
    parameters="-v av_LOGTYPE=\""$av_LOGTYPE"\""
elif [ -n "${av_FS}" ]; then
    parameters="-v av_FS=\""$av_FS"\""
elif [ -n "${av_FPAT}" ]; then
    parameters="-v av_FPAT=\""$av_FPAT"\""
elif [ -n "${av_FIELD_INDEX}" ]; then
    parameters="-v av_FIELD_INDEX=\""$av_FIELD_INDEX"\""
fi

echo $parameters


MYDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"




# awk -f analytics.awk $parameters $file


# 总记录条数
log_filepath=$@


echo "log file log_filepath: "$log_filepath

if [[ ! -f $log_filepath ]]; then
    echo "[Error] log file ["$log_filepath"] not found."
    exit 501;
fi


#检查awk版本号，必须是gawk 4.x版本
#  TODO: gawk版本检测的测试
#  如下的检测命令，只在cygwin上通过，其它平台未测试，待测试
awk_test=`awk -V |head -1 |awk 'BEGIN{FS=",";IGNORECASE=1} $1 ~ /GNU awk 4\..*/ {print $1}'`
if [[ -z awk_test ]]; then
    echo "[Error] require gawk 4.0+"
    echo "You can comment the below line, but as you risk."
    exit 502
fi



#定义web日志文件中字段位置
field_index_clientip=10
field_index_useragent=11


#两种计算行数的方式，
#   第一种 wc -l 似乎更快一点
#   第二种 awk 更准确，文件结尾无空行（非换行符结尾的文件）不会少算一行

#log_count=`wc -l ${log_filepath}`
log_count=`awk 'END{print NR}' ${log_filepath}`

echo "log file lines: "$log_count


# clientip grep

#awk 'BEGIN{FS=" "} $10!="" && $1!="#Fields:" {print $10}' |sort |uniq -c|sort -nr

# 单个ip请求数超过指定百分比，警告消息
suspect_client_ip_percent_threshold=1


#在awk脚本里$10,$11等使用别名，会慢一点，但维护性更好

cat $log_filepath| awk -v fi_cip="$field_index_clientip" \
    'BEGIN{FS=" "} $fi_cip!="" && $1!="#Fields:" {print $fi_cip}' |sort |uniq -c|sort -nr |\
awk -v total="${log_count}" -v threshold="${suspect_client_ip_percent_threshold}" \
    'BEGIN{
        suspect_count=0
        suspect_ips=""
        print "total: ",total;
        print "----- suspect client ip (threshold rate >",threshold,"%) ----------"
        printf "%16s  %6s %6s(%)\n","client_ip","count","rate";
    }
    {
        rate=$1/total*100;
        if(rate > threshold){
            printf "%16s  %6d %8.3f%\n",$2,$1,rate;
            suspect_count += 1;
            if(suspect_ips==""){
                suspect_ips = $2;
            }else{
                suspect_ips = suspect_ips"\n"$2;
            }
        }
    }
    END{
        print "----- suspect client ip END ----------";
        print "suspect count: ",suspect_count,"";
        # 将可疑ip地址写文件 tmp_suspect_ips.txt ,脚本结束后，注意清理这些临时文件
        print suspect_ips > "tmp_suspect_ips.txt"
    }'



# 检查异常ip的 useragent, 及最频繁的请求地址

# awk 中筛选client ip地址的部分
awk_filter=""
ips=""

while read line
    do
        echo 'ip: '$line
        if [[ ! -z "${line}" ]]; then
            if [[ -z "${awk_filter}" ]]; then
                awk_filter="\$10==\""$line"\""
            else
                awk_filter=$awk_filter" || \$10==\""$line"\""
            fi

            if [[ -z "${ips}" ]]; then
                ips=" "$line
            else
                ips=$ips" "$line
            fi
        fi
    done < tmp_suspect_ips.txt

echo "awk_filter: "$awk_filter
echo "ips: "$ips

#筛选出可疑ip请求的日志，输出到文件 tmp_suspect_request.log
awk -v ips="${ips}" -v fi_cip="$field_index_clientip" \
    '
    function in_array(arr,val){
        for(i in arr){
            if(arr[i]==val){
                return 1;
            }
        }
        return 0;
    }

    BEGIN{
        FS=" "
        split(ips,ip_a," ")
        for(i in ip_a){
            print "ip: ",i," -> ",ip_a[i]
        }
    }

    in_array(ip_a,$fi_cip) == 1 {
        #if(in_array(ip_a,$fi_cip)){
        #   print "Yes",$fi_cip;
        #}else{
        #   print "NNNNNNNOO",$fi_cip
        #}
        print $0
    }' $log_filepath > tmp_suspect_request.log





# 清理临时文件
rm tmp_suspect_ips.txt
rm tmp_suspect_request.log


