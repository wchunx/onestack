1.该脚本是基于官方openstack icehouse ubuntu部署文档写的allinone模式快捷安装脚本。
官方文档地址:http://docs.openstack.org/trunk/install-guide/install/apt/content/

2.安装的组件包括keystone, glance, nova, neutron, cinder, heat, ceilometer和horizon

3.网络模式为ml2 ovs gre模式。

4.安装之前应先根据实际情况修改配置文件one.conf,其中涉及mysql root用户密码和各组件数据库用户密码。
默认创建的dashboard登陆用户admin和demo，密码均为password。各组件同名用户用户名与密码一致，为组件名称。

5.脚本假设主机使用两块网卡，安装之前确保可联网，内网网卡已配置IP。one.conf中修改内外网IP:IN_IP和OUT_IP。
安装过程不会进行网络设置，只会创建br-ex和br-int,安装完后需要手动将网卡加到br-ex(ovs-vsctl add-port br-ex eth0),
并为br-ex配置IP。

6.修改完one.conf后，运行./one.sh进行安装。
