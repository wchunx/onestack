#!/bin/bash

set -x

##check root
if [ $(id -u) != "0" ];then
    echo "You must be root to run this script!\n"
    exit 1
fi

##变量设置
#MYSQL_PASSWD='123456'
#KEYSTONE_DB_PASSWD='keystone'
#CINDER_DB_PASSWD='cinder'
#NOVA_DB_PASSWD='nova'
#NEUTRON_DB_PASSWD='neutron'
#GLANCE_DB_PASSWD='glance'
#HEAT_DB_PASSWD='heat'

#ADMIN_PASSWD='password'
#DEMO_PASSWD='password'
#ADMIN_TOKEN='ADMIN'

#OUT_IP='192.168.60.43'
#IN_IP='100.100.100.100'

#VIRT_TYPE="qemu"
source one.conf

######################## 安装 #############################################
#locale-gen zh_CN.utf8

cat << MYSQL_PRESEED | debconf-set-selections
mysql-server-5.5 mysql-server/root_password password $MYSQL_PASSWD
mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PASSWD
mysql-server-5.5 mysql-server/start_on_boot boolean true
MYSQL_PRESEED

##mysql
apt-get -y --force-yes install mysql-server python-mysqldb
mysql -uroot -p$MYSQL_PASSWD -e "DELETE FROM mysql.user WHERE User='';"

sed -i -e "s/^\(bind-address\s*=\).*/\1 0.0.0.0/" /etc/mysql/my.cnf

sed -i -e "/bind-address/ a\\default-storage-engine = innodb\ncollation-server = utf8_general_ci\ninit-connect = 'SET NAMES utf8'\ncharacter-set-server = utf8" /etc/mysql/my.cnf

service mysql restart

##create database
mysql -uroot -p$MYSQL_PASSWD << EOF
DROP DATABASE IF EXISTS keystone;CREATE DATABASE keystone;
DROP DATABASE IF EXISTS glance;CREATE DATABASE glance;
DROP DATABASE IF EXISTS nova;CREATE DATABASE nova;
DROP DATABASE IF EXISTS cinder;CREATE DATABASE cinder;
DROP DATABASE IF EXISTS neutron;CREATE DATABASE neutron;
DROP DATABASE IF EXISTS heat;CREATE DATABASE heat;
GRANT ALL ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DB_PASSWD';
GRANT ALL ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DB_PASSWD';
GRANT ALL ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DB_PASSWD';
GRANT ALL ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DB_PASSWD';
GRANT ALL ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DB_PASSWD';
GRANT ALL ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DB_PASSWD';
GRANT ALL ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$CINDER_DB_PASSWD';
GRANT ALL ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_DB_PASSWD';
GRANT ALL ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DB_PASSWD';
GRANT ALL ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DB_PASSWD';
GRANT ALL ON heat.* TO 'heat'@'localhost' IDENTIFIED BY '$HEAT_DB_PASSWD';
GRANT ALL ON heat.* TO 'heat'@'%' IDENTIFIED BY '$HEAT_DB_PASSWD';
FLUSH PRIVILEGES;
EOF

##rabbitmq
apt-get -y --force-yes install rabbitmq-server

##keystone
apt-get -y --force-yes install keystone

#修改/etc/keystone/keystone.conf
## [DEFAULT]
## admin_token = ADMIN
## log_dir = /var/log/keystone
## [database]
## # The SQLAlchemy connection string used to connect to the database
## connection = mysql://keystone:keystone@100.100.100.100/keystone

sed -i "
        /admin_token/c admin_token=$ADMIN_TOKEN
        /log_dir/c log_dir=/var/log/keystone
        /keystone.db/s/^/#/
        /keystone.db/ a\connection = mysql://keystone:$KEYSTONE_DB_PASSWD@$IN_IP/keystone" /etc/keystone/keystone.conf

rm /var/lib/keystone/keystone.db
su -s /bin/sh -c "keystone-manage db_sync" keystone
service keystone restart

(crontab -l 2>&1 | grep -q token_flush) || \
echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/
keystone-tokenflush.log 2>&1' >> /var/spool/cron/crontabs/root

#创建用户,租户,角色,服务,endpoint
#keystone.sh创建admin和demo用户,密码视情况修改,keystone token默认ADMIN
chmod +x keystone.sh
./keystone.sh

cat > /root/admin-openrc.sh << _EOF_
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASSWD
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://$IN_IP:35357/v2.0
_EOF_
echo 'source /root/admin-openrc.sh' >> /root/.bashrc
source /root/admin-openrc.sh

cat > /root/demo-openrc.sh << _EOF_
export OS_USERNAME=demo
export OS_PASSWORD=$DEMO_PASSWD
export OS_TENANT_NAME=demo
export OS_AUTH_URL=http://$IN_IP:35357/v2.0
_EOF_

#检查keystone的安装
#keystone token-get
#keystone user-list
#keystone tenant-list
#keystone service-list
#keystone endpoint-list

###glance
apt-get -y --force-yes install glance python-glanceclient

#glance-api.conf
sed -i "
        /notification_driver = noop/c notification_driver = rabbit
        /rabbit_host/c rabbit_host = $IN_IP
        /sqlite.db/s/^/#/
        /sqlite.db/ a\connection = mysql://glance:$GLANCE_DB_PASSWD@$IN_IP/glance
        /auth_host/c auth_host = $IN_IP
        s/%SERVICE_TENANT_NAME%/service/g
        s/%SERVICE_USER%/glance/g
        s/%SERVICE_PASSWORD%/glance/g
        /flavor=/c flavor = keystone
        " /etc/glance/glance-api.conf

#glance-register.conf
sed -i "
        /sqlite.db/s/^/#/
        /sqlite.db/ a\connection = mysql://glance:$GLANCE_DB_PASSWD@$IN_IP/glance
        /auth_host/c auth_host = $IN_IP
        s/%SERVICE_TENANT_NAME%/service/g
        s/%SERVICE_USER%/glance/g
        s/%SERVICE_PASSWORD%/glance/g
        /flavor=/c flavor = keystone
        " /etc/glance/glance-registry.conf

su -s /bin/sh -c "glance-manage db_sync" glance
service glance-registry restart
service glance-api restart

#上传镜像
glance image-create --name "cirros-0.3.2-x86_64" --disk-format qcow2 \
--container-format bare --is-public True --progress < cirros-0.3.2-x86_64-disk.img
#验证
#glance image-list


####################### nova #############################
apt-get -y --force-yes install nova-api nova-cert nova-conductor nova-consoleauth \
nova-novncproxy nova-scheduler python-novaclient nova-compute-kvm python-guestfs

#disable virbr0
virsh net-destroy default
virsh net-autostart --disable default

#配置/etc/nova/nova.conf
cat <<NOVAconf >> /etc/nova/nova.conf

rpc_backend = rabbit
rabbit_host = $IN_IP
rabbit_password = guest

my_ip = $IN_IP
vnc_enabled = True
vncserver_listen = 0.0.0.0
vncserver_proxyclient_address = $IN_IP
novncproxy_base_url = http://$OUT_IP:6080/vnc_auto.html

auth_strategy = keystone

glance_host = $IN_IP

#networking
network_api_class = nova.network.neutronv2.api.API
neutron_url = http://$IN_IP:9696
neutron_auth_strategy = keystone
neutron_admin_tenant_name = service
neutron_admin_username = neutron
neutron_admin_password = neutron
neutron_admin_auth_url = http://$IN_IP:35357/v2.0
linuxnet_interface_driver = nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver
security_group_api = neutron

#metadata
service_neutron_metadata_proxy = true
neutron_metadata_proxy_shared_secret = $ADMIN_TOKEN

#ceilometer
instance_usage_audit = True
instance_usage_audit_period = hour
notify_on_state_change = vm_and_task_state
notification_driver = nova.openstack.common.notifier.rpc_notifier
notification_driver = ceilometer.compute.nova_notifier

[keystone_authtoken]
auth_uri = http://$IN_IP:5000
auth_host = $IN_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = nova
admin_password = nova
[database]
connection = mysql://nova:$NOVA_DB_PASSWD@$IN_IP/nova

[libvirt]
virt_type = $VIRT_TYPE
NOVAconf

#/etc/nova/nova-compute.conf
if [ -f "/etc/nova/nova-compute.conf" ];then
    sed -i "/virt_type/c virt_type=$VIRT_TYPE" /etc/nova/nova-compute.conf
fi

rm /var/lib/nova/nova.sqlite
su -s /bin/sh -c "nova-manage db sync" nova

dpkg-statoverride --update --add root root 0644 /boot/vmlinuz-$(uname -r)

cat <<_EOF_  > /etc/kernel/postinst.d/statoverride
#!/bin/sh
version="\$1"
# passing the kernel version is required
[ -z "\${version}" ] && exit 0
dpkg-statoverride --update --add root root 0644 /boot/vmlinuz-\${version}
_EOF_

chmod +x /etc/kernel/postinst.d/statoverride

cd /etc/init/; for i in $(ls nova-* | cut -d \. -f 1 | xargs); do sudo service $i restart; done

#验证
#nova-manage service list


################## neutron #####################
apt-get -y --force-yes install neutron-common neutron-server neutron-plugin-ml2 \
neutron-plugin-openvswitch-agent neutron-l3-agent neutron-dhcp-agent

#neutron.conf
SERVICE_TENANT_ID=$(keystone tenant-get service | awk '/ id / {print $4}')

sed -i "
/verbose =/ a\verbose = True\n\
auth_strategy = keystone\n\
rpc_backend = neutron.openstack.common.rpc.impl_kombu\n\
rabbit_host = $IN_IP\n\
rabbit_password = guest\n\
notify_nova_on_port_status_changes = True\n\
notify_nova_on_port_data_changes = True\n\
nova_url = http://$IN_IP:8774/v2\n\
nova_admin_username = nova\n\
nova_admin_tenant_id = $SERVICE_TENANT_ID\n\
nova_admin_password = nova\n\
nova_admin_auth_url = http://$IN_IP:35357/v2.0\n\
core_plugin = ml2\n\
service_plugins = router,firewall\n\
allow_overlapping_ips = True" /etc/neutron/neutron.conf

sed -i "
        /Ml2Plugin/s/^/#/
        /^service_provider/s/^/#/
        /neutron.sqlite/s/^/#/
        /neutron.sqlite/ a\connection = mysql://neutron:$NEUTRON_DB_PASSWD@$IN_IP/neutron
        /auth_host/c auth_host = $IN_IP
        s/%SERVICE_TENANT_NAME%/service/g
        s/%SERVICE_USER%/neutron/g
        s/%SERVICE_PASSWORD%/neutron/g
        /flavor=/c flavor = keystone
        " /etc/neutron/neutron.conf

#ml2_conf.ini
sed -i "
/\[ml2\]/ a\type_drivers = gre\n\
tenant_network_types = gre\n\
mechanism_drivers = openvswitch
/\[ml2_type_gre\]/ a\tunnel_id_ranges = 1:1000
/\[securitygroup\]/ a\\
firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver\n\
enable_security_group = True" /etc/neutron/plugins/ml2/ml2_conf.ini 

cat <<OVS >> /etc/neutron/plugins/ml2/ml2_conf.ini

[ovs]
local_ip = $IN_IP
tunnel_type = gre
enable_tunneling = True
OVS

#sysctl.conf
sed -i "s/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/
        s/#net.ipv4.conf.all.rp_filter=1/net.ipv4.conf.all.rp_filter=0/
        s/#net.ipv4.conf.default.rp_filter=1/net.ipv4.conf.default.rp_filter=0/" /etc/sysctl.conf

sysctl -p

#l3_agent.ini
sed -i "
/DEFAULT/ a\debug = True\n\
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver\n\
use_namespaces = True" /etc/neutron/l3_agent.ini

#dhcp_agent.ini
sed -i "
/DEFAULT/ a\debug = True\n\
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver\n\
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq\n\
use_namespaces = True" /etc/neutron/dhcp_agent.ini

#metadata_agent.ini
sed -i "
/debug =/c debug = True
/auth_url/c auth_url = http://$IN_IP:5000/v2.0
s/%SERVICE_TENANT_NAME%/service/g
s/%SERVICE_USER%/neutron/g
s/%SERVICE_PASSWORD%/neutron/g
/metadata_proxy_shared_secret =/c metadata_proxy_shared_secret = $ADMIN_TOKEN" /etc/neutron/metadata_agent.ini

#fwaas_driver.ini
sed -i '2,3s/^#//g' /etc/neutron/fwaas_driver.ini

#ovs
service openvswitch-switch restart
ovs-vsctl add-br br-int
ovs-vsctl add-br br-ex

cd /etc/init/; for i in $(ls neutron-* | cut -d \. -f 1 | xargs); do sudo service $i restart; done

################### cinder ######################
apt-get -y --force-yes install cinder-api cinder-scheduler lvm2 cinder-volume

#cinder.conf
cat <<CINDERconf >> /etc/cinder/cinder.conf

control_exchange = cinder
notification_driver = cinder.openstack.common.notifier.rpc_notifier

rpc_backend = cinder.openstack.common.rpc.impl_kombu
rabbit_host = $IN_IP
rabbit_port = 5672
rabbit_userid = guest
rabbit_password = guest

glance_host = $IN_IP

[keystone_authtoken]
auth_uri = http://$IN_IP:5000
auth_host = $IN_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = cinder
admin_password = cinder

[database]
connection = mysql://cinder:$CINDER_DB_PASSWD@$IN_IP/cinder
CINDERconf

su -s /bin/sh -c "cinder-manage db sync" cinder

dd if=/dev/zero of=/opt/cinder-volumes bs=1 count=0 seek=8G
losetup /dev/loop2 /opt/cinder-volumes
pvcreate /dev/loop2
vgcreate cinder-volumes /dev/loop2

sed -i '/^exit 0/ilosetup /dev/loop2 /opt/cinder-volumes' /etc/rc.local

service cinder-scheduler restart
service cinder-api restart
service cinder-volume restart
service tgt restart

################## heat #####################
apt-get -y --force-yes install heat-api heat-api-cfn heat-engine

#heat.conf
sed -i "
5 a\verbose = True\n\
log_dir=/var/log/heat\n\
rabbit_host = $IN_IP\n\
rabbit_password = guest\n\
heat_metadata_server_url = http://$IN_IP:8000\n\
heat_waitcondition_server_url = http://$IN_IP:8000/v1/waitcondition" /etc/heat/heat.conf

sed -i "/^connection/s/^/#/
/\[database\]/ a\connection = mysql://heat:$HEAT_DB_PASSWD@$IN_IP/heat" /etc/heat/heat.conf

sed -i "
/keystone_authtoken/ a\
auth_host = $IN_IP\n\
auth_port = 35357\n\
auth_protocol = http\n\
auth_uri = http://$IN_IP:5000/v2.0\n\
admin_tenant_name = service\n\
admin_user = heat\n\
admin_password = heat" /etc/heat/heat.conf

sed -i "/ec2authtoken/ a\auth_uri = http://$IN_IP:5000/v2.0" /etc/heat/heat.conf

rm /var/lib/heat/heat.sqlite

su -s /bin/sh -c "heat-manage db_sync" heat

service heat-api restart
service heat-api-cfn restart
service heat-engine restart

################### ceilometer ###################
apt-get -y --force-yes install ceilometer-api ceilometer-collector ceilometer-agent-central \
ceilometer-agent-notification ceilometer-alarm-evaluator \
ceilometer-alarm-notifier python-ceilometerclient \
ceilometer-agent-compute mongodb-server

service mongodb stop
rm /var/lib/mongodb/journal/prealloc.*
sed -i -e  "s/^\(bind_ip\s*=\).*/\1 0.0.0.0/" /etc/mongodb.conf 
service mongodb start

mongod --repair
mongo --host $IN_IP --eval '
db = db.getSiblingDB("ceilometer");
db.addUser({user: "ceilometer",
pwd: "ceilometer",
roles: [ "readWrite", "dbAdmin" ]})'

#ceilometer.conf
sed -i "
3 a\auth_strategy = keystone\n\
log_dir=/var/log/ceilometer\n\
rabbit_host = $IN_IP\n\
rabbit_password = guest" /etc/ceilometer/ceilometer.conf

sed -i "/^connection/s/^/#/
/\[database\]/ a\connection = mongodb://ceilometer:ceilometer@$IN_IP:27017/ceilometer" /etc/ceilometer/ceilometer.conf

sed -i "
/keystone_authtoken/ a\
auth_host = $IN_IP\n\
auth_port = 35357\n\
auth_protocol = http\n\
auth_uri = http://$IN_IP:5000/v2.0\n\
admin_tenant_name = service\n\
admin_user = ceilometer\n\
admin_password = ceilometer" /etc/ceilometer/ceilometer.conf

sed -i "
/service_credentials/ a\
os_auth_url = http://$IN_IP:5000/v2.0\n\
os_username = ceilometer\n\
os_tenant_name = service\n\
os_password = ceilometer" /etc/ceilometer/ceilometer.conf

sed -i "
/\[publisher\]/ a\metering_secret = $ADMIN_TOKEN" /etc/ceilometer/ceilometer.conf

cd /etc/init/; for i in $(ls ceilometer-* | cut -d \. -f 1 | xargs); do sudo service $i restart; done

################### horizon ####################
apt-get -y --force-yes install apache2 memcached libapache2-mod-wsgi openstack-dashboard
apt-get -y --purge remove openstack-dashboard-ubuntu-theme

sed -i '/firewall/s/False/True/g' /etc/openstack-dashboard/local_settings.py
sed -i '/TIME_ZONE/c TIME_ZONE = "Asia/Shanghai"' /etc/openstack-dashboard/local_settings.py

service apache2 restart
service memcached restart

#################### 网络配置 ####################
echo "You have to configure networking yourself"
echo "if eth0 is your external nic,you should run ovs-vsctl add-port br-ex eth0, and configure external ip for br-ex"

##################### 安装完成 #####################
echo "Install finished"
echo "Now you can login the dashboard
http://$OUT_IP/horizon
user:admin
password:$ADMIN_PASSWD"
