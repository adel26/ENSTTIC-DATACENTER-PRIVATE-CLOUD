resource "openstack_blockstorage_volume_v3" "tf_lab_volume" {
  name              = "tf_lab_volume"
  size              = 30
 # availability_zone = "nova"
 # volume_type       = "ceph"
}

