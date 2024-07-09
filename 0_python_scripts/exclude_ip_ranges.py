#!/bin/python3

# 导入库
import sys
import netaddr

# 读取传入参数
input_file = sys.argv[1]
exclude_file = sys.argv[2]
output_file = sys.argv[3]

# 初始化列表
input_networks = []
exclude_networks = []

# 只读模式打开文件，使用上下文管理器自动管理文件的打开和关闭
with open(input_file, 'r') as file:
    # 逐行读取文件
    for line in file:
        # 去除行首尾的空白字符（空格、换行符、制表符、回车符）
        ip = line.strip()
        try:
            # 筛除明显不是 IP 地址的行
            if '.' in ip or ':' in ip:
                # 将行转换后加入列表
                input_networks.append(netaddr.IPNetwork(ip))
        except:
            print(f"Invalid IP network: {ip} in {input_file}")
            sys.exit(1)

# 只读模式打开文件，使用上下文管理器自动管理文件的打开和关闭
with open(exclude_file, 'r') as file_b:
    # 逐行读取文件
    for line in file_b:
        # 去除行首尾的空白字符（空格、换行符、制表符、回车符）
        ip = line.strip()
        try:
            # 筛除明显不是 IP 地址的行
            if '.' in ip or ':' in ip:
                # 将行转换后加入列表
                exclude_networks.append(netaddr.IPNetwork(ip))
        except:
            print(f"Invalid IP network: {ip} in {exclude_file}")
            sys.exit(1)

# 创建 IPSet 对象
input_set = netaddr.IPSet(input_networks)
exclude_set = netaddr.IPSet(exclude_networks)

# 找出 input_set 中存在但 exclude_set 中不存在的 IP 网络
result_set = input_set - exclude_set

# 覆盖写入模式打开文件，使用上下文管理器自动管理文件的打开和关闭
with open(output_file, mode='w', encoding='utf-8') as file:
    # 筛除经计算后 IP 段被删干净的行（以防万一的测试，实际如果结果为空，for 循环内的命令本来也不会运行）
    if len(result_set.iter_cidrs()) >= 1:
        # 逐行写入计算后的地址段（受限于 CIDR 表达法，可能会转换出多个 CIDR 段以覆盖整个范围）
        for net in result_set.iter_cidrs():
            file.write(f"{net}\n")

