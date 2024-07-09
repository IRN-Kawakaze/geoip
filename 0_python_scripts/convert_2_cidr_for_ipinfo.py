#!/bin/python3

# 导入库
import sys
import ipaddress

# 读取传入参数
input_file = sys.argv[1]
output_file = sys.argv[2]

# 初始化列表
parameters = []

# 只读模式打开文件，使用上下文管理器自动管理文件的打开和关闭
with open(input_file, mode='r', encoding='utf-8-sig') as file:
    # 逐行读取文件
    for row in file:
        # 去除开头和（或）结尾的空白字符，并使用逗号进行分割（最多分割 2 次）
        line = row.strip().split(',', 2)
        # 筛除第一列和（或）第二列明显不是 IP 地址的行
        if ('.' in line[0] or ':' in line[0]) and ('.' in line[1] or ':' in line[1]):
            # 确保每行有且仅有三列数据
            if len(line) == 3:
                # 将重新分段后的数据加入列表
                parameters.append((line[0], line[1], line[2]))
            else:
                # 如果行数据不符合要求，则报错并退出
                print(f"Invalid line: {line}")
                sys.exit(1)

# 覆盖写入模式打开文件，使用上下文管理器自动管理文件的打开和关闭
with open(output_file, mode='w', encoding='utf-8') as file:
    # 逐个处理列表中的数据
    for param in parameters:
        # 设置起始和截止 IP 地址，并去除可能存在于开头和（或）结尾的空白字符
        start = ipaddress.ip_address(param[0].strip())
        end = ipaddress.ip_address(param[1].strip())

        # 将 IP 地址范围转换为 CIDR 格式
        cidr_list = ipaddress.summarize_address_range(start, end)

        # 逐行显示转换后的地址段（受限于 CIDR 表达法，可能会转换出多个 CIDR 段以覆盖整个范围）
        for cidr in cidr_list:
            file.write(f"{cidr},{param[2]}\n")

