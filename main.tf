/*
This script is a customizable Terraform configuration for setting up a DigitalOcean droplet running Docker, 
where you can deploy your application from the current working directory in a Docker container.

If your repo has a Dockerfile and docker-compose, use this to spin up a droplet running it.

Variables for the script (put then within terraform.tfvars):

do_token = "dop_v1_somekey"
droplet_name = "app_name"
ssh_key_fingerprint = "f8:8d:...."   # ssh-keygen -E md5 -lf ~/.ssh/id_rsa.pub
*/


terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

variable "do_token" {}
variable "droplet_name" {}
variable "ssh_key_fingerprint" {}

provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_droplet" "app" {
  image  = "ubuntu-18-04-x64"
  name   = var.droplet_name
  region = "fra1"
  size   = "s-1vcpu-1gb"

  # ssh-keygen -E md5 -lf ~/.ssh/id_rsa.pub
  ssh_keys = [var.ssh_key_fingerprint]

  connection {
    host        = self.ipv4_address
    user        = "root"
    type        = "ssh"
    private_key = file("~/.ssh/id_rsa")
    timeout     = "1m"
  }
  
  provisioner "remote-exec" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",

      # pull packages
      "apt update && apt -y upgrade",

      # swap file
      "sudo fallocate -l 1G /swapfile",
      "sudo chmod 600 /swapfile",
      "sudo mkswap /swapfile",
      "sudo swapon /swapfile",
      "echo '/swapfile none swap 0 0' | sudo tee -a /etc/fstab",

      # Digital ocean monitoring
      "curl -sSL https://agent.digitalocean.com/install.sh | sh",

      # install general tools
      "apt -o Dpkg::Options::='--force-confnew' install -y software-properties-common python-software-properties vim zsh git curl build-essential htop curl",

      # install docker
      "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io",
      "sudo systemctl enable --now docker",

      // install docker-compose
      "curl -L \"https://github.com/docker/compose/releases/download/1.28.5/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose",
      "chmod +x /usr/local/bin/docker-compose",

      # security
      "ufw allow 22",
      "ufw allow 80",
      "ufw --force enable"
    ]
  }
}


resource "null_resource" "delay" {
  provisioner "local-exec" {
    command = "sleep 60"
  }

  triggers = {
    droplet_id = digitalocean_droplet.app.id
  }
}

resource "null_resource" "provisioning" {
  depends_on = [null_resource.delay]

  connection {
    host        = digitalocean_droplet.app.ipv4_address
    user        = "root"
    type        = "ssh"
    private_key = file("~/.ssh/id_rsa")
    timeout     = "2m"
  }

  provisioner "local-exec" {
    command = <<-EOF
    scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no docker-compose.yml root@${digitalocean_droplet.app.ipv4_address}:/root/
    scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no requirements.txt root@${digitalocean_droplet.app.ipv4_address}:/root/
    scp -r -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no src/ root@${digitalocean_droplet.app.ipv4_address}:/root/
    scp -r -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no tests/ root@${digitalocean_droplet.app.ipv4_address}:/root/
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no root@${digitalocean_droplet.app.ipv4_address} 'cd /root && docker-compose up -d'
    EOF
  }
  
  triggers = {
    droplet_id = digitalocean_droplet.app.id
  }
}