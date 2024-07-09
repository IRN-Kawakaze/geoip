#!/bin/python3

# 导入库
import sys
import ipaddress

# 读取传入参数
input_file = sys.argv[1]
output_file = sys.argv[2]

# 初始化列表
ipv4_networks = []
ipv6_networks = []

# 只读模式打开文件，使用上下文管理器自动管理文件的打开和关闭
with open(input_file, 'r') as file:
    # 逐行读取文件，按 IP 版本丢入对应的数组
    for line in file:
        ip = line.strip()
        try:
            if '.' in ip:
                ipv4_networks.append(ipaddress.ip_network(ip, strict=False))
            elif ':' in ip:
                ipv6_networks.append(ipaddress.ip_network(ip, strict=False))
        except ValueError:
            print(f"Invalid IP network: {ip}")
            sys.exit(1)

# 合并地址段
merged_ipv4 = ipaddress.collapse_addresses(ipv4_networks)
merged_ipv6 = ipaddress.collapse_addresses(ipv6_networks)

# 覆盖写入模式打开文件，使用上下文管理器自动管理文件的打开和关闭
with open(output_file, mode='w', encoding='utf-8') as file:
    # 逐行写入结果
    for net in merged_ipv4:
        file.write(f"{net}\n")

    for net in merged_ipv6:
        file.write(f"{net}\n")

