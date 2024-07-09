## 相对 *ray 原始 geoip.dat 的已知变动（不排除存在未知变动）

1、文件体积大幅增加，对低配置的设备不友好。

2、采用 IPinfo 的 Free IP to Country + IP to ASN 作为境外数据源。

3、增加 loopback 数据集，仅包含回环地址。

4、参考 Loyalsoldier/geoip，采用 17mon/china_ip_list 和 gaoyifan/china-operator-ip 作为境内数据源。

5、参考 Loyalsoldier/geoip，增加 Cloudflare、CloudFront、Google 和 Telegram 数据集。

## 注意事项

1、除 CN 以外的地区代码数据集不包含一些已知的 Anycast IP 地址，例如：1.1.1.1、8.8.8.8。

2、CN 数据集未使用 IPinfo 内的数据。

3、以厂商名称命名的数据集包含该厂商所有 ASN 的 IP 段数据，并非单指某个产品，例如：Cloudflare。

4、以产品名称命名的数据集仅包含该产品所使用的 IP 段，例如：CloudFront。

## 手动生成方式

配置要求：

1、Debian 11 或更高版本。

2、至少 2 GiB 内存。

```
sudo apt update && sudo apt install git -y
git clone https://github.com/IRN-Kawakaze/geoip.git
cd ./geoip
```

```
bash ipinfo_2_geoip.sh "你的 IPinfo TOKEN"
```

## 特别感谢（排名不分先后）

参考和依赖：

[v2fly/geoip](https://github.com/v2fly/geoip)

[Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip)

数据源：

[IPinfo.io](https://ipinfo.io)

[17mon/china_ip_list](https://github.com/17mon/china_ip_list)

[gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip)

[Cloudflare](https://www.cloudflare.com/ips/)

[CloudFront](https://docs.aws.amazon.com/vpc/latest/userguide/aws-ip-work-with.html)

[Google](https://support.google.com/a/answer/10026322?hl=zh-Hans)

[Telegram](https://core.telegram.org/resources/cidr.txt)

