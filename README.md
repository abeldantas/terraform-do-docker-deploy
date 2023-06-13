# DigitalOcean Droplet Deployment

This repository includes a Terraform script for creating a new DigitalOcean Droplet and deploying a Docker containerized application.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html)
- A DigitalOcean account and a generated Personal Access Token.
- An SSH key added to the DigitalOcean account.

## Install Terraform

#### MacOS

```bash
brew install terraform
```

#### Windows
Download and install the .msi file from Terraform Downloads.

#### Linux

```bash
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform
```

#### Windows (Using Git Bash and Chocolatey)

First, install Chocolatey:

```bash
/bin/bash -c "$(curl -fsSL https://chocolatey.org/install.sh)"
```

Then, install Terraform:

```bash
choco install terraform
```

## Usage

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

Plan is optional.
The -auto-approve flag is optional, and is used to skip interactive approval of plan execution.

#### Variables

You can configure the behavior of the script by setting values in the terraform.tfvars file:

do_token - Your DigitalOcean API token.
droplet_name - The desired name of your droplet.
ssh_key_fingerprint - The fingerprint of the SSH key you want to use for the droplet.

Like this:

```bash
do_token = "dop_v1_somekey"
droplet_name = "app_name"
ssh_key_fingerprint = "c0:ff:ee..."   # ssh-keygen -E md5 -lf ~/.ssh/id_rsa.pub
```