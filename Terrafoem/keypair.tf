resource "openstack_compute_keypair_v2" "tf_lab_keypair" {
  name = "tf_lab_keypair"
}

output "ssh_keypair" {
  value = openstack_compute_keypair_v2.tf_lab_keypair.private_key
}








