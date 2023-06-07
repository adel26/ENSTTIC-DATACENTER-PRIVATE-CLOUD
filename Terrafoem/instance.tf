resource "openstack_compute_instance_v2" "tf_lab_vm" {
  name            = "tf_lab_vm"
  image_id        = "6b63ca09-7d80-46bf-8228-bce4c5483919"
  flavor_id       = openstack_compute_flavor_v2.tf_lab_flavor.id
  key_pair        = openstack_compute_keypair_v2.tf_lab_keypair.name
  security_groups = ["Default"] #this is the default security_group with all the access
  #security_groups = ["Lab_end"] #This is the second security_group with no access

  network {
    name = "provider"
  }
}

resource "openstack_compute_volume_attach_v2" "tf_lab_vm_volume_attach" {
  instance_id = openstack_compute_instance_v2.tf_lab_vm.id
  volume_id   = openstack_blockstorage_volume_v3.tf_lab_volume.id
}
