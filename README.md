# OSP13 Steps to configure a cluster (home lab)

## Hardware Setup

I’m using nested virtualisation on a Dell PowerEdge R810 with 384GB RAM and 4 CPUs. I have installed CentOS7 and OVS to manage VLANs, once the VMs are created, each requires a separate Virtual Bare Metal Control (virtualBMC) service. This is explained in a separate document.


## Deployment Steps

These are mostly derived and customised from: https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/13/html/director_installation_and_usage/installing-the-undercloud

## Configure SSL

https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/13/html/director_installation_and_usage/appe-ssltls_certificate_configuration

Then create “inject-trust-anchor-hiera.yaml”


## Undercloud Config

```
cat undercloud.conf  
[DEFAULT]
undercloud_hostname = osp13-director.momolab
local_ip = 192.168.200.1/24
undercloud_public_host = 192.168.1.230
undercloud_admin_host = 192.168.200.10
undercloud_nameservers = 192.168.1.150
undercloud_ntp_servers = 192.168.1.150
overcloud_domain_name = momolab
subnets = ctlplane-subnet
local_subnet = ctlplane-subnet
undercloud_service_certificate = /etc/pki/instack-certs/undercloud.pem
generate_service_certificate = false
local_interface = eth0
local_mtu = 1500
undercloud_debug = true
#undercloud_update_packages = false
enabled_drivers = pxe_ipmitool,pxe_drac,pxe_ilo
enabled_hardware_types = ipmi,redfish,ilo,idrac
 
[auth]
undercloud_admin_password = password
 
[ctlplane-subnet]
cidr = 192.168.200.0/24
dhcp_start = 192.168.200.5
dhcp_end = 192.168.200.24
inspection_iprange = 192.168.200.100,192.168.200.120
gateway = 192.168.200.1
masquerade = true
```

## Overcloud Images

I’ve decided to do these in my local registry:

```
(undercloud) [stack@osp13-director templates]$ cat ../scripts/local_registry.sh
# Added the octavia images, as they are not included by default.
# Ref: https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/13/html-single/director_installation_and_usage/index#configuring-a-container-image-source

# Get the images.
sudo openstack overcloud container image prepare \
  -e /usr/share/openstack-tripleo-heat-templates/environments/services-docker/octavia.yaml \
  -e /usr/share/openstack-tripleo-heat-templates/environments/ceph-ansible/ceph-ansible.yaml \
  --set ceph_namespace=registry.access.redhat.com/rhceph \
  --set ceph_image=rhceph-3-rhel7 \
  --namespace=registry.access.redhat.com/rhosp13 \
  --push-destination=192.168.200.1:8787 \
  --prefix=openstack- \
  --tag-from-label {version}-{release} \
  --output-env-file=/home/stack/templates/overcloud_images.yaml \
  --output-images-file /home/stack/local_registry_images.yaml

# Pull the container images to the undercloud.
sudo openstack overcloud container image upload \
  --config-file /home/stack/local_registry_images.yaml \
  --verbose

curl http://192.168.200.1:8787/v2/_catalog | jq .repositories[]
```



## Introspect Hardware

```
(undercloud) [stack@osp13-director templates]$ cat ../scripts/introspect.sh
openstack overcloud node import --validate-only ~/instackenv.json
openstack overcloud node import ~/instackenv.json
openstack baremetal node list
openstack overcloud node introspect --all-manageable --provide

openstack baremetal node set --property capabilities='profile:compute,boot_option:local'  osp13-compute0
openstack baremetal node set --property capabilities='profile:compute,boot_option:local'  osp13-compute1
openstack baremetal node set --property capabilities='profile:compute,boot_option:local'  osp13-compute2
openstack baremetal node set --property capabilities='profile:control,boot_option:local' osp13-controller0
openstack baremetal node set --property capabilities='profile:ceph-storage,boot_option:local' osp13-ceph0

openstack overcloud profiles list
```

## Create Custom Roles

```
Create your roles_data.yaml
Identify the components of your cluster, I’ve done one of the following for different uses:

openstack overcloud roles generate -o ~/roles/roles_data.yaml Controller ComputeDVR CephStorage

openstack overcloud roles generate -o ~/roles/roles_data.yaml Controller Compute CephStorage
```

**Note:** By default, CephStorage doesn’t get an external interface created so you need to add it in the relevant section.
E.g.:
```
  networks:
    - External
```

## Create Custom Network Settings:

Create your network_data.yaml
From: https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/13/html/advanced_overcloud_customization/basic-network-isolation

Section 9.2:

```
$ cp /usr/share/openstack-tripleo-heat-templates/network_data.yaml /home/stack/templates/
```

Make changes to the network as you see fit. I’ve only needed to change my external network.


## Generate Custom Templates

```
$ cat scripts/custom_templates.sh
/usr/share/openstack-tripleo-heat-templates/tools/process-templates.py \
-p /usr/share/openstack-tripleo-heat-templates \
-r /home/stack/roles/roles_data.yaml \
-n /home/stack/templates/network_data.yaml \
--safe \
-o /home/stack/generated-openstack-tripleo-heat-templates
```


## Octavia Configuration

All you need is to include:

```
  -e /usr/share/openstack-tripleo-heat-templates/environments/services/octavia.yaml \
  -e /home/stack/templates/octavia_timeouts.yaml \
```

```
$ cat /home/stack/templates/octavia_timeouts.yaml
parameter_defaults:
  OctaviaTimeoutClientData: 1200000
  OctaviaTimeoutMemberData: 1200000
```

## Ceph Ansible

Include:

```
  -e /usr/share/openstack-tripleo-heat-templates/environments/ceph-ansible/ceph-ansible.yaml \
  -e /home/stack/templates/ceph-extraconfig.yaml \
```

```
$ cat /home/stack/templates/ceph-extraconfig.yaml
parameter_defaults:
# added the line below in templates/node-info.yaml
  CephDefaultPoolSize: 1
  CephAnsibleDisksConfig:
    devices:
      - /dev/vdb
    journal_size: 512
    osd_scenario: collocated
#  ExtraConfig:
#    ceph::profile::params::osds: {}

  CephConfigOverrides:
# the line below is from: ttps://docs.openstack.org/project-deploy-guide/tripleo-docs/latest/features/ceph_config.html
    CephPoolDefaultSize: 1
    CephPoolDefaultPgNum: 32
    mon_max_pg_per_osd: 2000
# https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/13/html-single/deploying_an_overcloud_with_containerized_red_hat_ceph/index
  CephPools:
    - {"name": volumes, "pg_num": 128, "pgp_num": 128, "application": rbd, "size": 1}
    - {"name": vms, "pg_num": 128, "pgp_num": 128, "application": rbd, "size": 1}
    - {"name": images, "pg_num": 128, "pgp_num": 128, "application": rbd, "size": 1}
    - {"name": metrics, "pg_num": 128, "pgp_num": 128, "application": openstack_gnocchi, "size": 1}
    - {"name": backups, "pg_num": 128, "pgp_num": 128, "application": rbd, "size": 1}

```


## Network Isolation

For each OpenStack node, I have six interfaces (for each VM)  on the following vlans:

| NIC | Eth | VLAN ID | VLAN Description |
| --- | --- | --- | --- |
|NIC1| eth0| 10 |This is my control VLAN|
|NIC2| eth1| 3 |Storage VLAN |
|NIC3| eth2| 40| Sotrage Management VLAN|
|NIC4| eth3| 20| Internal API VLAN|
|NIC5| eth4| 50| Tenant VLAN| 
|NIC6| eth5| 0| External VLAN (My public network)|

Based on instructions from: https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/13/html/advanced_overcloud_customization/basic-network-isolation

Here we will use:
```
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/network-isolation.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/network-environment.yaml \
```

Ensure you customise /home/stack/generated-openstack-tripleo-heat-templates/environments/network-environment.yaml to point to multiple-nics instead of single-nic-vlans, as below:

```
  OS::TripleO::Controller::Net::SoftwareConfig:
    ../network/config/multiple-nics/controller.yaml
  # Port assignments for the Compute
  OS::TripleO::Compute::Net::SoftwareConfig:
    ../network/config/multiple-nics/compute.yaml
  # Port assignments for the CephStorage
  OS::TripleO::CephStorage::Net::SoftwareConfig:
    ../network/config/multiple-nics/ceph-storage.yaml
```

## Additional Configurations

### Extending mistral timeouts

Note: You’ll only need this if you have an old and slow network:

In `/etc/mistral/mistral.conf`, change the `rpc_response_timeout` to `600`, then `sudo systemctl restart openstack-mistral*`

Then in /etc/haproxy/haproxy.cfg add two lines to the `listen mistral` section:

```
timeout client 10m
timeout server 10m
```

And restart the service with `sudo systemctl restart haproxy'

### Node info

```
$ cat /home/stack/templates/node-info.yaml
parameter_defaults:
  OvercloudControllerFlavor: control
  OvercloudComputeFlavor: compute
  OvercloudCephStorageFlavor: ceph-storage
  ControllerCount: 1
  ComputeCount: 3
  CephStorageCount: 1
```

OR (if using DVR - not tested):

```
$ cat /home/stack/templates/node-info.yaml
parameter_defaults:
  OvercloudControllerFlavor: control
  OvercloudComputeDVRFlavor: compute
  OvercloudCephStorageFlavor: ceph-storage
  ControllerCount: 1
  ComputeDVRCount: 3
  CephStorageCount: 1
```

### Disable telemetry

This is useful if you are limited on resources.

```
$ cat /home/stack/templates/disable_telemetry.yaml
# This heat environment can be used to disable all of the telemetry services.
# It is most useful in a resource constrained environment or one in which
# telemetry is not needed.
# From: https://raw.githubusercontent.com/openstack/tripleo-heat-templates/master/environments/disable-telemetry.yaml

resource_registry:
  OS::TripleO::Services::CeilometerAgentCentral: OS::Heat::None
  OS::TripleO::Services::CeilometerAgentNotification: OS::Heat::None
  OS::TripleO::Services::CeilometerAgentIpmi: OS::Heat::None
  OS::TripleO::Services::ComputeCeilometerAgent: OS::Heat::None
  OS::TripleO::Services::GnocchiApi: OS::Heat::None
  OS::TripleO::Services::GnocchiMetricd: OS::Heat::None
  OS::TripleO::Services::GnocchiStatsd: OS::Heat::None
  OS::TripleO::Services::AodhApi: OS::Heat::None
  OS::TripleO::Services::AodhEvaluator: OS::Heat::None
  OS::TripleO::Services::AodhNotifier: OS::Heat::None
  OS::TripleO::Services::AodhListener: OS::Heat::None
  OS::TripleO::Services::Redis: OS::Heat::None

parameter_defaults:
  NotificationDriver: 'noop'
  GnocchiRbdPoolName: ''
```

### Network Config

When setting up networks, don't add a DNS server, and what this will do is allow you to resolve tenant VMs without any additional config, which is valuable for the OpenShift installation.

```
$ cat /home/stack/templates/network_config.yaml
parameter_defaults:
  DnsServers: ['192.168.1.150']
  StorageMtu: 9000
  StorageMgmtMtu: 9000
  InternalApiMtu: 9000
  TenantMtu: 9000
  ExternalMtu: 9000
```


## Deploy Scripts

Using centralised router (not DVR):
```
$ cat scripts/deploy-overcload.sh  
openstack overcloud deploy -v --templates  \
  --ntp-server 192.168.1.150 \
  -r /home/stack/roles/roles_data.yaml \
  -n /home/stack/templates/network_data.yaml \
  -e /home/stack/templates/overcloud_images.yaml \
  -e /home/stack/templates/node-info.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/ceph-ansible/ceph-ansible.yaml \
  -e /home/stack/templates/ceph-extraconfig.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/network-isolation.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/network-environment.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/services/octavia.yaml \
  -e /home/stack/templates/octavia_timeouts.yaml \
  -e /home/stack/inject-trust-anchor-hiera.yaml \
  -e /home/stack/templates/disable_telemetry.yaml \
  |tee overcloud_stack_deployment.log

```


Distributed Virtual Routing (DVR - Not tested yet):

```
$ cat scripts/deploy-overcload_dvr.sh  
openstack overcloud deploy -v --templates  \
  --ntp-server 192.168.1.150 \
  -r /home/stack/roles/roles_data_dvr.yaml \
  -n /home/stack/templates/network_data.yaml \
  -e /home/stack/templates/overcloud_images.yaml \
  -e /home/stack/templates/node-info-dvr.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates-dvr/environments/ceph-ansible/ceph-ansible.yaml \
  -e /home/stack/templates/ceph-extraconfig.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates-dvr/environments/neutron-ovs-dvr.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates-dvr/environments/network-isolation.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates-dvr/environments/network-environment.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates-dvr/environments/services/octavia.yaml \
  -e /home/stack/templates/octavia_timeouts.yaml \
  -e /home/stack/inject-trust-anchor-hiera.yaml \
  -e /home/stack/templates/disable_telemetry.yaml \
  |tee overcloud_stack_deployment.log
```




## Undercloud Config

```
cat undercloud.conf  
[DEFAULT]
undercloud_hostname = osp13-director.momolab
local_ip = 192.168.200.1/24
undercloud_public_host = 192.168.1.230
undercloud_admin_host = 192.168.200.10
undercloud_nameservers = 192.168.1.150
undercloud_ntp_servers = 192.168.1.150
overcloud_domain_name = momolab
subnets = ctlplane-subnet
local_subnet = ctlplane-subnet
undercloud_service_certificate = /etc/pki/instack-certs/undercloud.pem
generate_service_certificate = false
local_interface = eth0
local_mtu = 1500
undercloud_debug = true
#undercloud_update_packages = false
enabled_drivers = pxe_ipmitool,pxe_drac,pxe_ilo
enabled_hardware_types = ipmi,redfish,ilo,idrac
 
[auth]
undercloud_admin_password = password
 
[ctlplane-subnet]
cidr = 192.168.200.0/24
dhcp_start = 192.168.200.5
dhcp_end = 192.168.200.24
inspection_iprange = 192.168.200.100,192.168.200.120
gateway = 192.168.200.1
masquerade = true
```

## Overcloud Images

I’ve decided to do these in my local registry:

```
(undercloud) [stack@osp13-director templates]$ cat ../scripts/local_registry.sh
# Added the octavia images, as they are not included by default.
# Ref: https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/13/html-single/director_installation_and_usage/index#configuring-a-container-image-source

# Get the images.
sudo openstack overcloud container image prepare \
  -e /usr/share/openstack-tripleo-heat-templates/environments/services-docker/octavia.yaml \
  -e /usr/share/openstack-tripleo-heat-templates/environments/ceph-ansible/ceph-ansible.yaml \
  --set ceph_namespace=registry.access.redhat.com/rhceph \
  --set ceph_image=rhceph-3-rhel7 \
  --namespace=registry.access.redhat.com/rhosp13 \
  --push-destination=192.168.200.1:8787 \
  --prefix=openstack- \
  --tag-from-label {version}-{release} \
  --output-env-file=/home/stack/templates/overcloud_images.yaml \
  --output-images-file /home/stack/local_registry_images.yaml

# Pull the container images to the undercloud.
sudo openstack overcloud container image upload \
  --config-file /home/stack/local_registry_images.yaml \
  --verbose

curl http://192.168.200.1:8787/v2/_catalog | jq .repositories[]
```



## Introspect Hardware

```
(undercloud) [stack@osp13-director templates]$ cat ../scripts/introspect.sh
openstack overcloud node import --validate-only ~/instackenv.json
openstack overcloud node import ~/instackenv.json
openstack baremetal node list
openstack overcloud node introspect --all-manageable --provide

openstack baremetal node set --property capabilities='profile:compute,boot_option:local'  osp13-compute0
openstack baremetal node set --property capabilities='profile:compute,boot_option:local'  osp13-compute1
openstack baremetal node set --property capabilities='profile:compute,boot_option:local'  osp13-compute2
openstack baremetal node set --property capabilities='profile:control,boot_option:local' osp13-controller0
openstack baremetal node set --property capabilities='profile:ceph-storage,boot_option:local' osp13-ceph0

openstack overcloud profiles list
```

## Create Custom Roles

```
Create your roles_data.yaml
Identify the components of your cluster, I’ve done one of the following for different uses:

openstack overcloud roles generate -o ~/roles/roles_data.yaml Controller ComputeDVR CephStorage

openstack overcloud roles generate -o ~/roles/roles_data.yaml Controller Compute CephStorage
```

**Note:**  By default, CephStorage doesn’t get an external interface created so you need to add it in the relevant section in `roles_data.yaml`.

E.g.:
```
  networks:
    - External
```

## Create Custom Network Settings:

Create your network_data.yaml
From: https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/13/html/advanced_overcloud_customization/basic-network-isolation

Section 9.2:

```
$ cp /usr/share/openstack-tripleo-heat-templates/network_data.yaml /home/stack/templates/
```

Make changes to the network as you see fit. I’ve only needed to change my external network.


## Generate Custom Templates

```
$ cat scripts/custom_templates.sh
/usr/share/openstack-tripleo-heat-templates/tools/process-templates.py \
-p /usr/share/openstack-tripleo-heat-templates \
-r /home/stack/roles/roles_data.yaml \
-n /home/stack/templates/network_data.yaml \
--safe \
-o /home/stack/generated-openstack-tripleo-heat-templates
```


## Octavia Configuration

All you need is to include:

```
  -e /usr/share/openstack-tripleo-heat-templates/environments/services/octavia.yaml \
  -e /home/stack/templates/octavia_timeouts.yaml \
```

```
$ cat /home/stack/templates/octavia_timeouts.yaml
parameter_defaults:
  OctaviaTimeoutClientData: 1200000
  OctaviaTimeoutMemberData: 1200000
```

## Ceph Ansible

Include:

```
  -e /usr/share/openstack-tripleo-heat-templates/environments/ceph-ansible/ceph-ansible.yaml \
  -e /home/stack/templates/ceph-extraconfig.yaml \
```
Below is a specific setting for a single ceph node:

```
$ cat /home/stack/templates/ceph-extraconfig.yaml
parameter_defaults:
# added the line below in templates/node-info.yaml
  CephDefaultPoolSize: 1
  CephAnsibleDisksConfig:
    devices:
      - /dev/vdb
    journal_size: 512
    osd_scenario: collocated
#  ExtraConfig:
#    ceph::profile::params::osds: {}

  CephConfigOverrides:
# the line below is from: ttps://docs.openstack.org/project-deploy-guide/tripleo-docs/latest/features/ceph_config.html
    CephPoolDefaultSize: 1
    CephPoolDefaultPgNum: 32
    mon_max_pg_per_osd: 2000
# https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/13/html-single/deploying_an_overcloud_with_containerized_red_hat_ceph/index
  CephPools:
    - {"name": volumes, "pg_num": 128, "pgp_num": 128, "application": rbd, "size": 1}
    - {"name": vms, "pg_num": 128, "pgp_num": 128, "application": rbd, "size": 1}
    - {"name": images, "pg_num": 128, "pgp_num": 128, "application": rbd, "size": 1}
    - {"name": metrics, "pg_num": 128, "pgp_num": 128, "application": openstack_gnocchi, "size": 1}
    - {"name": backups, "pg_num": 128, "pgp_num": 128, "application": rbd, "size": 1}

```


Network Isolation

For each OpenStack node, I have six interfaces (on all VMs) configured for the following vlans:


|NIC| Eth| VLAN ID| VLAN Description|
| --- | --- | --- | --- |
|NIC1| eth0| 10| This is my control VLAN|
|NIC2| eth1| 30 | Storage VLAN|
|NIC3| eth2| 40| Sotrage Management VLAN|
|NIC4| eth3| 20| Internal API VLAN|
|NIC5| eth4| 50| Tenant VLAN| 
|NIC6| eth5| 0| External VLAN (My public network)|
  
Based on instructions from: https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/13/html/advanced_overcloud_customization/basic-network-isolation

Here we will use:
```
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/network-isolation.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/network-environment.yaml \
```

Ensure you customise /home/stack/generated-openstack-tripleo-heat-templates/environments/network-environment.yaml to point to multiple-nics instead of single-nic-vlans, as below:

```
  OS::TripleO::Controller::Net::SoftwareConfig:
    ../network/config/multiple-nics/controller.yaml
  # Port assignments for the Compute
  OS::TripleO::Compute::Net::SoftwareConfig:
    ../network/config/multiple-nics/compute.yaml
  # Port assignments for the CephStorage
  OS::TripleO::CephStorage::Net::SoftwareConfig:
    ../network/config/multiple-nics/ceph-storage.yaml
```

## Additional Configurations

### Extending mistral timeouts

Note: You’ll only need this if you have an old and slow network:

In `/etc/mistral/mistral.conf`, change the `rpc_response_timeout` to `600`, then `sudo systemctl restart openstack-mistral*`

Then in /etc/haproxy/haproxy.cfg add two lines to the `listen mistral` section:

```
timeout client 10m
timeout server 10m
```

And restart the service with `sudo systemctl restart haproxy'

### Node info

```
$ cat /home/stack/templates/node-info.yaml
parameter_defaults:
  OvercloudControllerFlavor: control
  OvercloudComputeFlavor: compute
  OvercloudCephStorageFlavor: ceph-storage
  ControllerCount: 1
  ComputeCount: 3
  CephStorageCount: 1
```

OR (if using DVR - not tested):

```
$ cat /home/stack/templates/node-info.yaml
parameter_defaults:
  OvercloudControllerFlavor: control
  OvercloudComputeDVRFlavor: compute
  OvercloudCephStorageFlavor: ceph-storage
  ControllerCount: 1
  ComputeDVRCount: 3
  CephStorageCount: 1
```

### Disable telemetry

This might be useful if you have limited resources.

```
$ cat /home/stack/templates/disable_telemetry.yaml
# This heat environment can be used to disable all of the telemetry services.
# It is most useful in a resource constrained environment or one in which
# telemetry is not needed.
# From: https://raw.githubusercontent.com/openstack/tripleo-heat-templates/master/environments/disable-telemetry.yaml

resource_registry:
  OS::TripleO::Services::CeilometerAgentCentral: OS::Heat::None
  OS::TripleO::Services::CeilometerAgentNotification: OS::Heat::None
  OS::TripleO::Services::CeilometerAgentIpmi: OS::Heat::None
  OS::TripleO::Services::ComputeCeilometerAgent: OS::Heat::None
  OS::TripleO::Services::GnocchiApi: OS::Heat::None
  OS::TripleO::Services::GnocchiMetricd: OS::Heat::None
  OS::TripleO::Services::GnocchiStatsd: OS::Heat::None
  OS::TripleO::Services::AodhApi: OS::Heat::None
  OS::TripleO::Services::AodhEvaluator: OS::Heat::None
  OS::TripleO::Services::AodhNotifier: OS::Heat::None
  OS::TripleO::Services::AodhListener: OS::Heat::None
  OS::TripleO::Services::Redis: OS::Heat::None

parameter_defaults:
  NotificationDriver: 'noop'
  GnocchiRbdPoolName: ''
```

### Network Config

When setting up networks, don't add a DNS server, and what this will do is allow you to resolve tenant VMs without any additional config, which is valuable for the OpenShift installation.

```
$ cat /home/stack/templates/network_config.yaml
parameter_defaults:
  DnsServers: ['192.168.1.150']
  StorageMtu: 9000
  StorageMgmtMtu: 9000
  InternalApiMtu: 9000
  TenantMtu: 9000
  ExternalMtu: 9000
```


## Deploy Scripts

Using centralised router (not DVR):
```
$ cat scripts/deploy-overcload.sh  
openstack overcloud deploy -v --templates  \
  --ntp-server 192.168.1.150 \
  -r /home/stack/roles/roles_data.yaml \
  -n /home/stack/templates/network_data.yaml \
  -e /home/stack/templates/overcloud_images.yaml \
  -e /home/stack/templates/node-info.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/ceph-ansible/ceph-ansible.yaml \
  -e /home/stack/templates/ceph-extraconfig.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/network-isolation.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/network-environment.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates/environments/services/octavia.yaml \
  -e /home/stack/templates/octavia_timeouts.yaml \
  -e /home/stack/inject-trust-anchor-hiera.yaml \
  -e /home/stack/templates/disable_telemetry.yaml \
  |tee overcloud_stack_deployment.log

```


Distributed Virtual Routing (DVR - Not tested yet):

```
$ cat scripts/deploy-overcload_dvr.sh  
openstack overcloud deploy -v --templates  \
  --ntp-server 192.168.1.150 \
  -r /home/stack/roles/roles_data_dvr.yaml \
  -n /home/stack/templates/network_data.yaml \
  -e /home/stack/templates/overcloud_images.yaml \
  -e /home/stack/templates/node-info-dvr.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates-dvr/environments/ceph-ansible/ceph-ansible.yaml \
  -e /home/stack/templates/ceph-extraconfig.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates-dvr/environments/neutron-ovs-dvr.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates-dvr/environments/network-isolation.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates-dvr/environments/network-environment.yaml \
  -e /home/stack/generated-openstack-tripleo-heat-templates-dvr/environments/services/octavia.yaml \
  -e /home/stack/templates/octavia_timeouts.yaml \
  -e /home/stack/inject-trust-anchor-hiera.yaml \
  -e /home/stack/templates/disable_telemetry.yaml \
  |tee overcloud_stack_deployment.log
```


