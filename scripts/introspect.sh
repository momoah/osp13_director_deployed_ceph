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


