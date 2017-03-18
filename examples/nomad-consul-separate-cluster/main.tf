# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A NOMAD CLUSTER AND A SEPARATE CONSUL CLUSTER IN AWS
# These templates show an example of how to use the nomad-cluster module to deploy a Nomad cluster in AWS. This cluster
# connects to Consul running in a separate cluster.
#
# We deploy two Auto Scaling Groups (ASGs) for Nomad: one with a small number of Nomad server nodes and one with a
# larger number of Nomad client nodes. Note that these templates assume that the AMI you provide via the
# nomad_ami_id input variable is built from the examples/nomad-consul-ami/nomad-consul.json Packer template.
#
# We also deploy one ASG for Consul which has a small number of Consul server nodes. Note that these templates assume
# that the AMI you provide via the consul_ami_id input variable is built from the examples/consul-ami/consul.json
# Packer template in the Consul AWS Blueprint.
# ---------------------------------------------------------------------------------------------------------------------

provider "aws" {
  region = "${var.aws_region}"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE NOMAD SERVER NODES
# ---------------------------------------------------------------------------------------------------------------------

module "nomad_servers" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/nomad-aws-blueprint.git//modules/nomad-cluster?ref=v0.0.1"
  source = "../../modules/nomad-cluster"

  cluster_name  = "${var.nomad_cluster_name}-server"
  instance_type = "t2.micro"

  # You should typically use a fixed size of 3 or 5 for your Nomad server cluster
  min_size         = "${var.num_nomad_servers}"
  max_size         = "${var.num_nomad_servers}"
  desired_capacity = "${var.num_nomad_servers}"

  ami_id    = "${var.ami_id}"
  user_data = "${data.template_file.user_data_nomad_server.rendered}"

  vpc_id             = "${data.aws_vpc.default.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  # To make testing easier, we allow requests from any IP address here but in a production deployment, we strongly
  # recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.
  allowed_ssh_cidr_blocks     = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = "${var.ssh_key_name}"
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH IAM POLICIES FOR CONSUL
# To allow our server Nodes to automatically discover the Consul servers, we need to give them the IAM permissions from
# the Consul AWS Blueprint's consul-iam-policies module.
# ---------------------------------------------------------------------------------------------------------------------

module "consul_iam_policies_servers" {
  source = "git::git@github.com:gruntwork-io/consul-aws-blueprint.git//modules/consul-iam-policies?ref=v0.0.2"

  iam_role_id = "${module.nomad_servers.iam_role_id}"
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH NOMAD SERVER NODE WHEN IT'S BOOTING
# This script will configure and start Nomad
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_nomad_server" {
  template = "${file("${path.module}/user-data-nomad-server.sh")}"

  vars {
    num_servers       = "${var.num_nomad_servers}"
    cluster_tag_key   = "${var.cluster_tag_key}"
    cluster_tag_value = "${var.consul_cluster_name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CONSUL SERVER NODES
# ---------------------------------------------------------------------------------------------------------------------

module "consul_servers" {
  source = "git::git@github.com:gruntwork-io/consul-aws-blueprint.git//modules/consul-cluster?ref=v0.0.2"

  cluster_name  = "${var.consul_cluster_name}-server"
  cluster_size  = "${var.num_consul_servers}"
  instance_type = "t2.micro"

  # The EC2 Instances will use these tags to automatically discover each other and form a cluster
  cluster_tag_key   = "${var.cluster_tag_key}"
  cluster_tag_value = "${var.consul_cluster_name}"

  ami_id    = "${var.ami_id}"
  user_data = "${data.template_file.user_data_consul_server.rendered}"

  vpc_id             = "${data.aws_vpc.default.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  # To make testing easier, we allow Consul and SSH requests from any IP address here but in a production
  # deployment, we strongly recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.
  allowed_ssh_cidr_blocks     = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = "${var.ssh_key_name}"
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH CONSUL SERVER EC2 INSTANCE WHEN IT'S BOOTING
# This script will configure and start Consul
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_consul_server" {
  template = "${file("${path.module}/user-data-consul-server.sh")}"

  vars {
    cluster_tag_key   = "${var.cluster_tag_key}"
    cluster_tag_value = "${var.consul_cluster_name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE NOMAD CLIENT NODES
# ---------------------------------------------------------------------------------------------------------------------

module "nomad_clients" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/nomad-aws-blueprint.git//modules/nomad-cluster?ref=v0.0.1"
  source = "../../modules/nomad-cluster"

  cluster_name  = "${var.nomad_cluster_name}-client"
  instance_type = "t2.micro"

  # To keep the example simple, we are using a fixed-size cluster. In real-world usage, you could use auto scaling
  # policies to dynamically resize the cluster in response to load.
  min_size         = "${var.num_nomad_clients}"
  max_size         = "${var.num_nomad_clients}"
  desired_capacity = "${var.num_nomad_clients}"

  ami_id    = "${var.ami_id}"
  user_data = "${data.template_file.user_data_nomad_client.rendered}"

  vpc_id             = "${data.aws_vpc.default.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  # To make testing easier, we allow Consul and SSH requests from any IP address here but in a production
  # deployment, we strongly recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.
  allowed_ssh_cidr_blocks     = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = "${var.ssh_key_name}"
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH IAM POLICIES FOR CONSUL
# To allow our client Nodes to automatically discover the Consul servers, we need to give them the IAM permissions from
# the Consul AWS Blueprint's consul-iam-policies module.
# ---------------------------------------------------------------------------------------------------------------------

module "consul_iam_policies_clients" {
  source = "git::git@github.com:gruntwork-io/consul-aws-blueprint.git//modules/consul-iam-policies?ref=v0.0.2"

  iam_role_id = "${module.nomad_clients.iam_role_id}"
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH CLIENT NODE WHEN IT'S BOOTING
# This script will configure and start Consul and Nomad
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_nomad_client" {
  template = "${file("${path.module}/user-data-nomad-client.sh")}"

  vars {
    cluster_tag_key   = "${var.cluster_tag_key}"
    cluster_tag_value = "${var.consul_cluster_name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CLUSTERS IN THE DEFAULT VPC AND AVAILABILITY ZONES
# Using the default VPC and all availability zones makes this example easy to run and test, but in a production
# deployment, we strongly recommend deploying into a custom VPC and private subnets (the latter specified via the
# subnet_ids parameter in the consul-cluster module).
# ---------------------------------------------------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "all" {}