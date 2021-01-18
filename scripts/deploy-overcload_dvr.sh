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
  --timeout=20 \
  |tee overcloud_stack_deployment.log
