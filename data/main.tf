# lets first define the varibles that this file will used

variable "instance_name" {
  default = "default_instance_name"
}
variable "instance_type" {
  default = "t2.micro"
}
variable "key_pair_name" {
  default = "default_key_pair_name"
}
variable "jenkins_git_repo_link" {
  default = "https://github.com/name/no-repo.git"
}

# lets generate a ssh key pair locally

resource "tls_private_key" "local_resource" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# local keypair the prem key

resource "local_file" "private_key_pem" {
  content         = tls_private_key.local_resource.private_key_pem
  filename        = "${path.module}/terraform-key.pem"
  file_permission = "0600"
}

# this public key will be uploaded to the aws 
resource "aws_key_pair" "generated_key" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.local_resource.public_key_openssh
}

# amazon linux verison let keep it latest as default

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  owners = ["amazon"]
}


# security key for ssh
resource "aws_security_group" "ssh_access" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ec2 instance 

resource "aws_instance" "web_server" {
  ami             = data.aws_ami.amazon_linux.id
  instance_type   = var.instance_type
  key_name        = aws_key_pair.generated_key.key_name
  security_groups = [aws_security_group.ssh_access.name]

  # User data script to run on startup
  user_data = <<-EOF
              #!/bin/bash
              # Update packages
              sudo yum update -y
              
              # Installing---Docker
              sudo amazon-linux-extras install docker -y
              sudo service docker start
              sudo usermod -aG docker ec2-user
              sudo yum install git -y
              # Install Docker Compose
              sudo curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              sudo chmod +x /usr/local/bin/docker-compose
              
              mkdir -p /home/ec2-user/jenkins
              cd /home/ec2-user/jenkins
              git clone ${var.jenkins_git_repo_link}
              cd jenkins-docker-setup
              
              # Start Docker container 
              docker-compose up -d
              EOF

  tags = {
    Name = var.instance_name
  }
}


# -------------------------------
# Outputs
# -------------------------------
output "ec2_public_ip" {
  value = aws_instance.web_server.public_ip
}

output "private_key_path" {
  value = local_file.private_key_pem.filename
}
