resource "openstack_compute_flavor_v2" "tf_lab_flavor" {
  name  = "tf_lab_flavor"
  ram   = "4096"
  vcpus = "2"
  disk  = "20"
}

resource "openstack_compute_flavor_access_v2" "tf_lab_flavor_access" {
  tenant_id = "398a3d6a0a3c460483c18cfa5445093f"
  flavor_id = openstack_compute_flavor_v2.tf_lab_flavor.id
}
