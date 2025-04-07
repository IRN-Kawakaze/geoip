#!/bin/bash

# 出错立刻退出
set -e

# 函数-检查依赖
check_dep(){
    # 检查 Python 脚本是否存在
    [[ -f "${python_script_path}/convert_2_cidr_for_ipinfo.py" ]] || { echo "ERROR: Need convert_2_cidr_for_ipinfo.py script."; exit 1; }
    [[ -f "${python_script_path}/exclude_ip_ranges.py" ]] || { echo "ERROR: Need exclude_ip_ranges.py script."; exit 1; }
    [[ -f "${python_script_path}/merge_ip_ranges.py" ]] || { echo "ERROR: Need merge_ip_ranges.py script."; exit 1; }
}

# 函数-部署依赖
deploy_dep() {
    # 如果已安装 netaddr 库，则不重复安装
    (python3 -c 'import netaddr; print(netaddr.__version__)' &> /dev/null) || python_dep=('python3' 'python3-netaddr')

    # 安装依赖软件
    sudo apt-get update
    sudo apt-get install 7zip git "${python_dep[@]}" wget -y
    wget "${wget_opt[@]}" 'https://go.dev/dl/go1.22.4.linux-amd64.tar.gz' -O 'go.tar.gz'
    sudo rm -rf '/usr/local/go'
    sudo tar -C '/usr/local' -zxf 'go.tar.gz'
    export PATH=$PATH:/usr/local/go/bin

    # 为 Debian 12 的 7zip 做兼容
    if { ! which 7z &>/dev/null && which 7zz &>/dev/null; }; then
        if [[ "$(which 7zz)" == '/usr/bin/7zz' && ! -f '/usr/bin/7z' ]]; then
            sudo ln -s '/usr/bin/7zz' '/usr/bin/7z'
        fi
    fi

    # 拉取 geoip 仓库
    rm -rf "${geoip_repo_path}"
    git clone 'https://github.com/v2fly/geoip.git' "${geoip_repo_path}"

    # 创建工作目录
    rm -rf "${src_data_path}"
    rm -rf "${region_cidr_data_path}"
    rm -rf "${need_merge_data_path}"
    rm -rf "${geoip_input_path}"
    mkdir -p "${src_data_path}"
    mkdir -p "${region_cidr_data_path}"
    mkdir -p "${need_merge_data_path}"
    mkdir -p "${geoip_input_path}"

    # 拉取其他来源数据
    wget "${wget_opt[@]}" 'https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt' -O "${src_data_path}/src_17mon_china_ip_list.txt"
    wget "${wget_opt[@]}" 'https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt' -O "${src_data_path}/src_gaoyifan_china.txt"
    wget "${wget_opt[@]}" 'https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china6.txt' -O "${src_data_path}/src_gaoyifan_china6.txt"
    wget "${wget_opt[@]}" 'https://www.cloudflare.com/ips-v4' -O "${src_data_path}/src_cloudflare_ips-v4.txt"
    wget "${wget_opt[@]}" 'https://www.cloudflare.com/ips-v6' -O "${src_data_path}/src_cloudflare_ips-v6.txt"
    wget "${wget_opt[@]}" 'https://ip-ranges.amazonaws.com/ip-ranges.json' -O "${src_data_path}/src_cloudfront_ip-ranges.json"
    wget "${wget_opt[@]}" 'https://www.gstatic.com/ipranges/goog.json' -O "${src_data_path}/src_google_goog.json"
    wget "${wget_opt[@]}" 'https://www.gstatic.com/ipranges/cloud.json' -O "${src_data_path}/src_google_cloud.json"
    wget "${wget_opt[@]}" 'https://core.telegram.org/resources/cidr.txt' -O "${src_data_path}/src_telegram_cidr.txt"

    # 拉取 IPinfo 数据，最后拉取，避免浪费每日配额
    rm -f 'country_asn.csv.gz'
    rm -f 'country_asn.csv'
    wget "${wget_opt[@]}" "https://ipinfo.io/data/free/country_asn.csv.gz?token=${ipinfo_token}" -O 'country_asn.csv.gz'
    7z x 'country_asn.csv.gz'
    mv 'country_asn.csv' "${src_data_path}/country_asn.csv"
}

# 函数-数据处理
proc_data() {
    # 将 IPinfo 原始数据转为 CIDR 格式，顺带过滤无效行
    echo 'Converting to CIDR...'
    python3 "${python_script_path}/convert_2_cidr_for_ipinfo.py" "${src_data_path}/country_asn.csv" "${src_data_path}/country_asn_cidr.csv" || \
    { echo "ERROR: Convert to CIDR failed."; exit 1; }

    # 制作一份仅有 IP 段和地区代码的数据
    awk -F ',' '{print $1,$2}' "${src_data_path}/country_asn_cidr.csv" > "${src_data_path}/cidr_and_region.csv"

    # 创建地区代码数组，将所有数据里存在的地区代码转为小写字母加入数组
    region_codes=()
    while read -r line; do
        region_codes+=("${line,,}")
    done <<< "$(awk -F ' ' '{print $2}' "${src_data_path}/cidr_and_region.csv" | sort -u | sed '/^$/d')"

    # 按地区代码对数据分组
    for code in "${region_codes[@]}"; do
        grep " ${code^^}$" "${src_data_path}/cidr_and_region.csv" | awk -F ' ' '{print $1}' > "${region_cidr_data_path}/${code}.txt"
    done

    # 运行函数“排除 Anycast IP 段”
    exclude_anycast

    # 运行对应函数以处理特殊数据
    proc_cn_data
    proc_cf_data
    proc_cft_data
    proc_google_data
    proc_tg_data
    proc_loopback_data

    # 为特殊处理的数据添加伪地区代码
    region_codes+=("cloudflare")
    region_codes+=("cloudfront")
    region_codes+=("google")
    region_codes+=("telegram")
    region_codes+=("loopback")

    # 将 CIDR 格式的数据进行合并，顺带检查 IP 段的合法性
    for code in "${region_codes[@]}"; do
        echo "Merging: ${code}."
        python3 "${python_script_path}/merge_ip_ranges.py" "${need_merge_data_path}/${code}.txt" "${geoip_input_path}/${code}.txt" || \
        { echo "ERROR: Merge IP ranges failed."; exit 1; }
    done
}

# 函数-排除 Anycast IP 段
exclude_anycast() {
    # 添加 Anycast 段合集，起始及每个 cat 之后须加空行防止重叠
    {
        echo
        cat "${src_data_path}/src_cloudflare_ips-v4.txt"; echo
        cat "${src_data_path}/src_cloudflare_ips-v6.txt"; echo
        echo '1.0.0.0/24'
        echo '1.1.1.0/24'
        echo '2606:4700:4700::/112'
        echo '8.8.8.8/32'
        echo '8.8.4.4/32'
        echo '2001:4860:4860::/112'
        echo '208.67.222.0/24'
        echo '208.67.220.0/24'
        echo '2620:119:35::35/112'
        echo '2620:119:53::53/112'
        echo '2620:0:ccc::2/112'
        echo '2620:0:ccd::2/112'
        echo '119.29.29.29/32'
        echo '119.28.28.28/32'
    } > "${src_data_path}/src_anycast_ip_ranges.txt"

    # 逐个地区排除 Anycast IP 段
    for code in "${region_codes[@]}"; do
        echo "Excluding from: ${code}."
        python3 "${python_script_path}/exclude_ip_ranges.py" "${region_cidr_data_path}/${code}.txt" "${src_data_path}/src_anycast_ip_ranges.txt" "${need_merge_data_path}/${code}.txt" || \
        { echo "ERROR: Exclude anycast IP ranges failed."; exit 1; }
    done
}

# 函数-处理 CN 数据
proc_cn_data() {
    # 声明局部变量
    local code='cn'

    # 合并数据，覆盖掉 IPinfo 的 CN 数据，必须添加空行以防首行内容未追加在新的一行
    {
        echo
        cat "${src_data_path}/src_17mon_china_ip_list.txt"; echo
        cat "${src_data_path}/src_gaoyifan_china.txt"; echo
        cat "${src_data_path}/src_gaoyifan_china6.txt"; echo
    } > "${need_merge_data_path}/${code}.txt"
}

# 函数-处理 Cloudflare 数据
proc_cf_data() {
    # 声明局部变量
    local code='cloudflare'

    # 筛选出 Cloudflare 的数据
    {
        grep ',AS13335,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS14789,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS132892,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS133877,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS139242,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS202623,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS203898,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS209242,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS394536,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS395747,' "${src_data_path}/country_asn_cidr.csv"
    } | awk -F ',' '{print $1}' > "${need_merge_data_path}/${code}.txt"

    # 合并官方公开数据，必须添加空行以防首行内容未追加在新的一行
    {
        echo
        cat "${src_data_path}/src_cloudflare_ips-v4.txt"; echo
        cat "${src_data_path}/src_cloudflare_ips-v6.txt"; echo
        echo '1.0.0.0/24'
        echo '1.1.1.0/24'
    } >> "${need_merge_data_path}/${code}.txt"
}

# 函数-处理 CloudFront 数据
proc_cft_data() {
    # 声明局部变量
    local code='cloudfront'

    # 筛选出 CFT 的 IP 段
    jq -r '.prefixes[], .ipv6_prefixes[] | select(.service == "CLOUDFRONT") | .ip_prefix, .ipv6_prefix | select(. != null)' \
    < "${src_data_path}/src_cloudfront_ip-ranges.json" > "${need_merge_data_path}/${code}.txt"
}

# 函数-处理 Google 数据
proc_google_data() {
    # 声明局部变量
    local code='google'

    # 筛选出 Google 的数据
    {
        grep ',AS6432,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS13949,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS15169,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS16550,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS16591,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS19425,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS19448,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS19527,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS22577,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS22859,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS26684,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS26910,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS32381,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS36039,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS36040,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS36383,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS36384,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS36385,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS36411,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS36492,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS36520,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS36561,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS36987,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS40873,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS41264,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS43515,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS45566,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS55023,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS139070,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS139190,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS214609,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS214611,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS394089,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS394507,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS394639,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS395973,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS396982,' "${src_data_path}/country_asn_cidr.csv"
    } | awk -F ',' '{print $1}' > "${need_merge_data_path}/${code}.txt"

    # 合并官方公开数据
    {
        jq -r '.prefixes[] | .ipv4Prefix, .ipv6Prefix | select(. != null)' \
        < "${src_data_path}/src_google_goog.json"
        jq -r '.prefixes[] | .ipv4Prefix, .ipv6Prefix | select(. != null)' \
        < "${src_data_path}/src_google_cloud.json"
    } >> "${need_merge_data_path}/${code}.txt"
}

# 函数-处理 Telegram 数据
proc_tg_data() {
    # 声明局部变量
    local code='telegram'

    # 筛选出 Telegram 的数据
    {
        grep ',AS44907,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS59930,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS62014,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS62041,' "${src_data_path}/country_asn_cidr.csv"
        grep ',AS211157,' "${src_data_path}/country_asn_cidr.csv"
    } | awk -F ',' '{print $1}' > "${need_merge_data_path}/${code}.txt"

    # 合并官方公开数据，必须添加空行以防首行内容未追加在新的一行
    {
        echo
        cat "${src_data_path}/src_telegram_cidr.txt"; echo
    } >> "${need_merge_data_path}/${code}.txt"
}

# 函数-处理回环地址数据
proc_loopback_data() {
    # 声明局部变量
    local code='loopback'

    # 添加回环地址
    {
        echo '127.0.0.0/8'
        echo '::1/128'
    } > "${need_merge_data_path}/${code}.txt"
}

# 函数-创建配置文件
create_conf() {
    # 初始化配置文件
    cat /dev/null > "${geoip_repo_path}/config.json"
    cat << 'EOF' > "${geoip_repo_path}/config.json"
{
    "input": [
EOF

    # 添加各地区代码的配置
    for code in "${region_codes[@]}"; do
        cat << EOF >> "${geoip_repo_path}/config.json"
        {
            "type": "text",
            "action": "add",
            "args": {
                "name": "${code}",
                "uri": "${geoip_input_path}/${code}.txt"
            }
        },
EOF
    done

    # 增加 Private 数据
    # 添加剩余配置
    cat << 'EOF' >> "${geoip_repo_path}/config.json"
        {
            "type": "private",
            "action": "add",
            "args": {
                "name": "private"
            }
        }
    ],
    "output": [
        {
            "type": "v2rayGeoIPDat",
            "action": "output",
            "args": {
                "outputName": "geoip.dat"
            }
        },
        {
            "type": "text",
            "action": "output"
        }
    ]
}

EOF
}

# 函数-生成 dat 文件
gen_dat() {
    # 删除非必要文件
    rm -f "${geoip_repo_path}/config-example.json"
    rm -rf "${geoip_repo_path}/output"

    # 进入工作目录
    cd "${geoip_repo_path}"

    # 生成 geoip.dat
    go mod download
    go run ./ || { echo "ERROR: Generate geoip.dat failed."; exit 1; }

    # 计算校验和
    (cd "${geoip_repo_path}/output/dat/" && sha256sum 'geoip.dat' > 'geoip.dat.sha256')

    # 提示运行结束
    echo -e "\033[32m""INFO: Finish.""\033[0m"
}

# 函数-主函数
main() {
    # 设置常量
    ipinfo_token="$1"; [[ -z "${ipinfo_token}" ]] && { echo "ERROR: You need enter the IPinfo token as \$1."; exit 1; }
    dir="$(cd "$(dirname "$0")" && pwd)"; [[ -z "${dir}" ]] && { echo "ERROR: Get work directory failed."; exit 1; }
    python_script_path="${dir}/0_python_scripts"
    src_data_path="${dir}/1_src_data"
    region_cidr_data_path="${dir}/2_region_cidr_data"
    need_merge_data_path="${dir}/3_need_merge_data"
    geoip_repo_path="${dir}/geoip"
    geoip_input_path="${geoip_repo_path}/geoip_input_data_dir"

    # 根据传入参数判断运行环境，以决定是否显示下载进度条
    wget_opt=("-q" "--show-progress")
    [[ "$2" == "GitHub" ]] && unset 'wget_opt[1]'

    # 运行“函数-检查依赖”
    check_dep

    # 运行“函数-部署依赖”
    deploy_dep

    # 运行“函数-数据处理”
    proc_data

    # 运行“函数-创建配置文件”
    create_conf

    # 运行“函数-生成 dat 文件”
    gen_dat
}

# 运行“函数-主函数”
main "${@}"

