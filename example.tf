# Configure the Alicloud Provider
variable access_key = "ACCESS_KEY_HERE"
variable secret_key = "SECRET_KEY_HERE"
variable region = "REGION"

provider "alicloud" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

data "alicloud_instance_types" "2c4g" {
  cpu_core_count = 2
  memory_size = 4
}

data "alicloud_images" "default" {
  name_regex  = "^ubuntu"
  most_recent = true
  owners      = "system"
}

# Create a web server
resource "alicloud_instance" "web" {
  image_id          = "${data.alicloud_images.default.images.0.id}"
  internet_charge_type  = "PayByBandwidth"

  instance_type        = "${data.alicloud_instance_types.2c4g.instance_types.0.id}"
  system_disk_category = "cloud_efficiency"
  security_groups      = ["${alicloud_security_group.default.id}"]
  instance_name        = "web"
  vswitch_id = "vsw-abc12345"
}

# Create security group
resource "alicloud_security_group" "default" {
  name        = "default"
  description = "default"
  vpc_id = "vpc-abc12345"
}

###
### Kubernetes - multi-AZ
###

variable "name" {
  default = "my-first-3az-k8s"
}

data "alicloud_zones" "main" {
  available_resource_creation = "VSwitch"
}

data "alicloud_instance_types" "instance_types_1_master" {
  availability_zone    = "${data.alicloud_zones.main.zones.0.id}"
  cpu_core_count       = 2
  memory_size          = 4
  kubernetes_node_role = "Master"
}
data "alicloud_instance_types" "instance_types_2_master" {
  availability_zone    = "${lookup(data.alicloud_zones.main.zones[(length(data.alicloud_zones.main.zones) - 1) % length(data.alicloud_zones.main.zones)], "id")}"
  cpu_core_count       = 2
  memory_size          = 4
  kubernetes_node_role = "Master"
}
data "alicloud_instance_types" "instance_types_3_master" {
  availability_zone    = "${lookup(data.alicloud_zones.main.zones[(length(data.alicloud_zones.main.zones) - 2) % length(data.alicloud_zones.main.zones)], "id")}"
  cpu_core_count       = 2
  memory_size          = 4
  kubernetes_node_role = "Master"
}

data "alicloud_instance_types" "instance_types_1_worker" {
  availability_zone    = "${data.alicloud_zones.main.zones.0.id}"
  cpu_core_count       = 2
  memory_size          = 4
  kubernetes_node_role = "Worker"
}
data "alicloud_instance_types" "instance_types_2_worker" {
  availability_zone    = "${lookup(data.alicloud_zones.main.zones[(length(data.alicloud_zones.main.zones) - 1) % length(data.alicloud_zones.main.zones)], "id")}"
  cpu_core_count       = 2
  memory_size          = 4
  kubernetes_node_role = "Worker"
}
data "alicloud_instance_types" "instance_types_3_worker" {
  availability_zone    = "${lookup(data.alicloud_zones.main.zones[(length(data.alicloud_zones.main.zones) - 2) % length(data.alicloud_zones.main.zones)], "id")}"
  cpu_core_count       = 2
  memory_size          = 4
  kubernetes_node_role = "Worker"
}
resource "alicloud_vpc" "foo" {
  name       = "${var.name}"
  cidr_block = "10.1.0.0/21"
}

resource "alicloud_vswitch" "vsw1" {
  name              = "${var.name}"
  vpc_id            = "${alicloud_vpc.foo.id}"
  cidr_block        = "10.1.1.0/24"
  availability_zone = "${data.alicloud_zones.main.zones.0.id}"
}

resource "alicloud_vswitch" "vsw2" {
  name              = "${var.name}"
  vpc_id            = "${alicloud_vpc.foo.id}"
  cidr_block        = "10.1.2.0/24"
  availability_zone = "${lookup(data.alicloud_zones.main.zones[(length(data.alicloud_zones.main.zones) - 1) % length(data.alicloud_zones.main.zones)], "id")}"
}

resource "alicloud_vswitch" "vsw3" {
  name              = "${var.name}"
  vpc_id            = "${alicloud_vpc.foo.id}"
  cidr_block        = "10.1.3.0/24"
  availability_zone = "${lookup(data.alicloud_zones.main.zones[(length(data.alicloud_zones.main.zones) - 2) % length(data.alicloud_zones.main.zones)], "id")}"
}

resource "alicloud_nat_gateway" "nat_gateway" {
  name          = "${var.name}"
  vpc_id        = "${alicloud_vpc.foo.id}"
  specification = "Small"
}

resource "alicloud_snat_entry" "snat_entry_1" {
  snat_table_id     = "${alicloud_nat_gateway.nat_gateway.snat_table_ids}"
  source_vswitch_id = "${alicloud_vswitch.vsw1.id}"
  snat_ip           = "${alicloud_eip.eip.ip_address}"
}

resource "alicloud_snat_entry" "snat_entry_2" {
  snat_table_id     = "${alicloud_nat_gateway.nat_gateway.snat_table_ids}"
  source_vswitch_id = "${alicloud_vswitch.vsw2.id}"
  snat_ip           = "${alicloud_eip.eip.ip_address}"
}

resource "alicloud_snat_entry" "snat_entry_3" {
  snat_table_id     = "${alicloud_nat_gateway.nat_gateway.snat_table_ids}"
  source_vswitch_id = "${alicloud_vswitch.vsw3.id}"
  snat_ip           = "${alicloud_eip.eip.ip_address}"
}

resource "alicloud_eip" "eip" {
  name      = "${var.name}"
  bandwidth = "100"
}

resource "alicloud_eip_association" "eip_asso" {
  allocation_id = "${alicloud_eip.eip.id}"
  instance_id   = "${alicloud_nat_gateway.nat_gateway.id}"
}

resource "alicloud_cs_kubernetes" "k8s" {
  name                      = "${var.name}"
  vswitch_ids               = ["${alicloud_vswitch.vsw1.id}", "${alicloud_vswitch.vsw2.id}", "${alicloud_vswitch.vsw3.id}"]
  new_nat_gateway           = true
  master_instance_types     = ["${data.alicloud_instance_types.instance_types_1_master.instance_types.0.id}", "${data.alicloud_instance_types.instance_types_2_master.instance_types.0.id}", "${data.alicloud_instance_types.instance_types_3_master.instance_types.0.id}"]
  worker_instance_types     = ["${data.alicloud_instance_types.instance_types_1_worker.instance_types.0.id}", "${data.alicloud_instance_types.instance_types_2_worker.instance_types.0.id}", "${data.alicloud_instance_types.instance_types_3_worker.instance_types.0.id}"]
  worker_numbers            = [1, 2, 3]
  master_disk_category      = "cloud_ssd"
  worker_disk_size          = 50
  worker_data_disk_category = "cloud_ssd"
  worker_data_disk_size     = 50
  password                  = "Yourpassword1234"
  pod_cidr                  = "192.168.1.0/16"
  service_cidr              = "192.168.2.0/24"
  enable_ssh                = true
  slb_internet_enabled      = true
  node_cidr_mask            = 25
  install_cloud_monitor     = true
}