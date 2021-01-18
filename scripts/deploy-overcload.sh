source ~/stackrc
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
  -e /home/stack/templates/inject-trust-anchor-hiera.yaml \
  -e /home/stack/templates/controller-extraconfig.yaml \
  |tee overcloud_stack_deployment.log
