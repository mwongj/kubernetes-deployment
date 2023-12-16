resource "proxmox_vm_qemu" "control_plane" {
  count             = 1

  name              = "control-plane-${count.index}.k8s.cluster.ad.wongway.io"
  target_node       = "${var.pm_node}"
  agent		    = 1

  clone             = "ubuntu-2404-cloudinit-template"

  os_type           = "cloud-init"
  qemu_os	    = "other"
  cores             = 4
  sockets           = 1
  cpu               = "host"
  memory            = 4096
  scsihw            = "virtio-scsi-pci"
  bootdisk          = "scsi0"

  disk {
    size            = "10G"
    type            = "scsi"
    storage         = "${var.pm_storage}"
    iothread        = 0
  }

  network {
    model           = "virtio"
    bridge          = "vmbr5"
  }

  pool		    = "${var.pm_pool}"

  # cloud-init settings
  # adjust the ip and gateway addresses as needed
  ipconfig0         = "ip=10.0.5.3/24,gw=10.0.5.254"
  sshkeys = file("${var.ssh_key_file}")

  connection {
    host	    = "${self.ssh_host}"
    user	    = "ubuntu"
    type	    = "ssh"
    private_key     = "${self.ssh_private_key}"
  }

  # Reboot the machines to get the correct hostname set for DNS
  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname control-plane-${count.index}.k8s.cluster.ad.wongway.io",
      "sudo reboot"
    ]
  }

  # Ignore changes to the network
  ## MAC address is generated on every apply, causing
  ## TF to think this needs to be rebuilt on every apply
  lifecycle {
     ignore_changes = [
       network,
       pool
     ]
  }

}

resource "proxmox_vm_qemu" "worker_nodes" {
  count             = 2

  name              = "worker-${count.index}.k8s.cluster.ad.wongway.io"
  target_node       = "${var.pm_node}"
  agent		    = 1

  clone             = "ubuntu-2404-cloudinit-template"

  os_type           = "cloud-init"
  qemu_os	    = "other"
  cores             = 2
  sockets           = 1
  cpu               = "host"
  memory            = 2048
  scsihw            = "virtio-scsi-pci"
  bootdisk          = "scsi0"

  disk {
    size            = "10G"
    type            = "scsi"
    storage         = "${var.pm_storage}"
    iothread        = 0
  }

  network {
    model           = "virtio"
    bridge          = "vmbr5"
  }

  pool		    = "${var.pm_pool}"

  # cloud-init settings
  # adjust the ip and gateway addresses as needed
  ipconfig0         = "ip=dhcp"
  sshkeys = file("${var.ssh_key_file}")

  connection {
    host	    = "${self.ssh_host}"
    user	    = "ubuntu"
    type	    = "ssh"
    private_key     = "${self.ssh_private_key}"
  }

  # Reboot the machines to get the correct hostname set for DNS
  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname worker-${count.index}.k8s.cluster.ad.wongway.io",
      "sudo reboot"
    ]
  }

  # Ignore changes to the network
  ## MAC address is generated on every apply, causing
  ## TF to think this needs to be rebuilt on every apply
  lifecycle {
     ignore_changes = [
       network,
       pool
     ]
  }
}

locals {
  control_plane_ips = proxmox_vm_qemu.control_plane.*.default_ipv4_address
  worker_node_ips = proxmox_vm_qemu.worker_nodes.*.default_ipv4_address
}

resource "local_file" "ansible_inventory" {
  filename = "inventory.ini"
  content = templatefile("${path.module}/templates/inventory.tftpl",
    {
      suffix	= ".${var.k8s_domain}"
      user	= "ubuntu"
      control-plane = local.control_plane_ips
      worker-nodes  = local.worker_node_ips
    }
  )
}
