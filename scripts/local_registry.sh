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

