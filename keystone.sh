#!/bin/bash

#ADMIN_PASSWORD="password"
#DEMO_PASSWORD="password"
#IN_IP="100.100.100.100"
source one.conf

export OS_SERVICE_TOKEN=ADMIN
export OS_SERVICE_ENDPOINT=http://$IN_IP:35357/v2.0

##create user
keystone user-create --name=admin --pass=password --email=admin@example.com
keystone user-create --name=demo --pass=password --email=demo@example.com
keystone user-create --name=glance --pass=glance --email=glance@example.com
keystone user-create --name=nova --pass=nova --email=nova@example.com
keystone user-create --name=neutron --pass=neutron --email=neutron@example.com
keystone user-create --name=cinder --pass=cinder --email=cinder@example.com
keystone user-create --name=heat --pass=heat --email=heat@example.com
keystone user-create --name=ceilometer --pass=ceilometer --email=ceilometer@example.com

##create tenant
keystone tenant-create --name=admin --description="Admin Tenant"
keystone tenant-create --name=demo --description="Demo Tenant"
keystone tenant-create --name=service --description="Service Tenant"

##create role
keystone role-create --name=admin
keystone role-create --name heat_stack_user

##link user,role and tenant
keystone user-role-add --user=admin --tenant=admin --role=admin
keystone user-role-add --user=admin --role=_member_ --tenant=admin
keystone user-role-add --user=demo --role=_member_ --tenant=demo
keystone user-role-add --user=glance --tenant=service --role=admin
keystone user-role-add --user=nova --tenant=service --role=admin
keystone user-role-add --user neutron --tenant service --role admin
keystone user-role-add --user=cinder --tenant=service --role=admin
keystone user-role-add --user=heat --tenant=service --role=admin
keystone user-role-add --user=ceilometer --tenant=service --role=admin

##create service
keystone service-create --name=keystone --type=identity \
--description="OpenStack Identity"

keystone service-create --name=glance --type=image \
--description="OpenStack Image Service"

keystone service-create --name=nova --type=compute \
--description="OpenStack Compute"

keystone service-create --name neutron --type network \
--description "OpenStack Networking"

keystone service-create --name=cinder --type=volume \
--description="OpenStack Block Storage"

keystone service-create --name=cinderv2 --type=volumev2 \
--description="OpenStack Block Storage v2"

keystone service-create --name=heat --type=orchestration \
--description="Orchestration"

keystone service-create --name=heat-cfn --type=cloudformation \
--description="Orchestration CloudFormation"

keystone service-create --name=ceilometer --type=metering \
--description="Telemetry"

##create endpoint
keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ identity / {print $2}') \
--publicurl=http://$IN_IP:5000/v2.0 \
--internalurl=http://$IN_IP:5000/v2.0 \
--adminurl=http://$IN_IP:35357/v2.0

keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ image / {print $2}') \
--publicurl=http://$IN_IP:9292 \
--internalurl=http://$IN_IP:9292 \
--adminurl=http://$IN_IP:9292

keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ compute / {print $2}') \
--publicurl=http://$IN_IP:8774/v2/%\(tenant_id\)s \
--internalurl=http://$IN_IP:8774/v2/%\(tenant_id\)s \
--adminurl=http://$IN_IP:8774/v2/%\(tenant_id\)s

keystone endpoint-create \
--service-id $(keystone service-list | awk '/ network / {print $2}') \
--publicurl http://$IN_IP:9696 \
--adminurl http://$IN_IP:9696 \
--internalurl http://$IN_IP:9696

keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ volume / {print $2}') \
--publicurl=http://$IN_IP:8776/v1/%\(tenant_id\)s \
--internalurl=http://$IN_IP:8776/v1/%\(tenant_id\)s \
--adminurl=http://$IN_IP:8776/v1/%\(tenant_id\)s

keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ volumev2 / {print $2}') \
--publicurl=http://$IN_IP:8776/v2/%\(tenant_id\)s \
--internalurl=http://$IN_IP:8776/v2/%\(tenant_id\)s \
--adminurl=http://$IN_IP:8776/v2/%\(tenant_id\)s

keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ orchestration / {print $2}') \
--publicurl=http://$IN_IP:8004/v1/%\(tenant_id\)s \
--internalurl=http://$IN_IP:8004/v1/%\(tenant_id\)s \
--adminurl=http://$IN_IP:8004/v1/%\(tenant_id\)s

keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ cloudformation / {print $2}') \
--publicurl=http://$IN_IP:8000/v1 \
--internalurl=http://$IN_IP:8000/v1 \
--adminurl=http://$IN_IP:8000/v1

keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ metering / {print $2}') \
--publicurl=http://$IN_IP:8777 \
--internalurl=http://$IN_IP:8777 \
--adminurl=http://$IN_IP:8777
