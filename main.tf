provider "aws" {
  region = var.region
}

locals {
  tags = {
    Owner       = "Dext"
    Environment = "Wordpress"
  }
}

data "aws_subnet_ids" "all" {
  vpc_id = module.vpc.vpc_id
  depends_on = [
    module.vpc.public_subnets
  ]
}

data "template_cloudinit_config" "user_data_wp" {
  count         = var.wp_instances
  gzip          = false
  base64_encode = true
  part {
    content_type = "text/x-shellscript"
    content      = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname "${lower(var.name)}-${format("%02d", count.index + 1)}"
    hostname
    sudo amazon-linux-extras install -y php7.2
    sudo yum install -y httpd mysql
    sudo systemctl start httpd
    sudo systemctl enable httpd
    sudo usermod -a -G apache ec2-user
    sudo chown -R ec2-user:apache /var/www
    sudo chmod 2775 /var/www && find /var/www -type d -exec sudo chmod 2775 {} \;
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    sudo mv wp-cli.phar /usr/local/bin/wp
    cd /var/www/html
    wp core download
    cp -p wp-config-sample.php wp-config.php
    sed -i 's/database_name_here/${var.db_name}/' wp-config.php
    sed -i 's/username_here/${var.db_user}/' wp-config.php
    sed -i 's/password_here/${module.db_default.db_pass}/' wp-config.php
    sed -i 's/localhost/${module.db_default.db_instance_address}/' wp-config.php
    sed -i '/put your unique phrase here/d' wp-config.php
    curl https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php 
    sudo chown -R ec2-user:apache /var/www

    if [[ `hostname` == "wordpress-01" ]]; then
      cd /tmp
      curl -LJ https://github.com/piroff/wordpress/tarball/main -o wordpress.tar.gz
      tar xzf wordpress.tar.gz
      find . -name blogpost_body.txt -exec mv {} ./ \;
      find . -name cron.sh -exec mv {} ./ \;
      chown ec2-user:ec2-user blogpost_body.txt cron.sh
      chmod +x cron.sh
      sed -i 's/DB_USER/${var.db_user}/' cron.sh
      sed -i 's/DB_PASS/${module.db_default.db_pass}/' cron.sh
      sed -i 's/DB_NAME/${var.db_name}/' cron.sh
      sed -i 's/DB_ADDR/${module.db_default.db_instance_address}/' cron.sh
      mv cron.sh /home/ec2-user/
      echo "0 3 * * 0 /home/ec2-user/cron.sh > /dev/null 2>&1" | tee /var/spool/cron/ec2-user
      cd /var/www/html
      wp core install --url="${module.alb.lb_dns_name}" --title="Dext" --admin_user="${var.db_user}" --admin_password="${module.db_default.db_pass}" --admin_email="my@ma.il"
      wp post delete $(wp post list --post_status=publish --format=ids)
      wp post delete $(wp post list --post_status=trash --format=ids)
      wp post create /tmp/blogpost_body.txt --post_title='Linux namespaces' --post_status='publish'
    fi
    EOF
  }
}


################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source = "./modules/vpc"

  name = "${title(var.name)}"
  cidr = var.vpc_cidr_block

  azs              = ["${var.region}a", "${var.region}b"]
  public_subnets   = ["192.168.0.0/28", "192.168.0.16/28"]
  private_subnets  = ["192.168.0.32/28", "192.168.0.48/28"]
  database_subnets = ["192.168.0.64/28", "192.168.0.80/28"]

  create_database_subnet_group = true

  tags = local.tags
}

module "security_group" {
  source = "./modules/secgroup"

  name        = "${title(var.name)}"
  description = "Security group for EC2 instance"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["ssh-tcp", "http-80-tcp", "all-icmp"]
  egress_rules        = ["all-all"]

  tags = local.tags
}

module "security_group_rds" {
  source = "./modules/secgroup"

  name        = "${var.name}-rds"
  description = "Complete MySQL example security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      description = "MySQL access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  tags = local.tags
}


################################################################################
# EC2 Module
################################################################################

module "ec2_complete" {
  source = "./modules/ec2"

  count = var.wp_instances
  name  = "${title(var.name)}-${format("%02d", count.index + 1)}"

  ami                         = var.ami_id
  instance_type               = var.instance_type
  availability_zone           = element(module.vpc.azs, 0)
  subnet_id                   = element(module.vpc.public_subnets, 0)
  vpc_security_group_ids      = [module.security_group.security_group_id]
  associate_public_ip_address = true
  key_name                    = "public.key"

  user_data_base64 = data.template_cloudinit_config.user_data_wp[count.index].rendered

  enable_volume_tags = false
  root_block_device = [
    {
      encrypted   = true
      volume_size = var.ec2_ebs_size
      tags = {
        Name = "${title(var.name)}-ebs-${format("%02d", count.index + 1)}"
      }
    },
  ]

  tags = local.tags
}


################################################################################
# RDS Module
################################################################################

module "db_default" {
  source = "./modules/rds"

  identifier = "${var.name}-db"

  create_db_option_group    = false
  create_db_parameter_group = false

  engine               = "mysql"
  engine_version       = "8.0.20"
  family               = "mysql8.0" # DB parameter group
  major_engine_version = "8.0"      # DB option group
  instance_class       = var.rds_instance_class

  allocated_storage = 20

  name                   = var.db_name
  username               = var.db_user
  create_random_password = true
  random_password_length = 12
  port                   = 3306

  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_group_rds.security_group_id]

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = local.tags
}


################################################################################
# Private key
################################################################################

resource "tls_private_key" "ssh" {
  algorithm   = "RSA"
  ecdsa_curve = "2048"
}

resource "aws_key_pair" "ssh_pulic_key" {
  key_name   = "public.key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  sensitive_content = tls_private_key.ssh.private_key_pem
  filename          = "credentials/private_key.pem"
  file_permission   = "0400"
}


################################################################################
# Application Load Balancer
################################################################################

module "alb" {

  source = "./modules/alb"

  name = "${var.name}-alb"

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  security_groups = [module.security_group.security_group_id]
  subnets         = module.vpc.public_subnets

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  http_tcp_listener_rules = [
    {
      http_tcp_listener_index = 0
      priority                = 3
      actions = [{
        type         = "fixed-response"
        content_type = "text/plain"
        status_code  = 200
        message_body = "This is a fixed response"
      }]

      conditions = [{
        http_headers = [{
          http_header_name = "x-Gimme-Fixed-Response"
          values           = ["yes", "please", "right now"]
        }]
      }]
    },
    {
      http_tcp_listener_index = 0
      priority                = 5000
      actions = [{
        type        = "redirect"
        status_code = "HTTP_302"
        host        = "www.youtube.com"
        path        = "/watch"
        query       = "v=dQw4w9WgXcQ"
        protocol    = "HTTPS"
      }]

      conditions = [{
        query_strings = [{
          key   = "video"
          value = "random"
        }]
      }]
    },
  ]

  target_groups = [
    {
      name_prefix          = "WP-"
      backend_protocol     = "HTTP"
      backend_port         = 80
      target_type          = "instance"
      deregistration_delay = 10
      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 6
        protocol            = "HTTP"
        matcher             = "200-399"
      }
      protocol_version = "HTTP1"
      targets = {
        my_ec2_01 = {
          target_id = module.ec2_complete[0].id
          port      = 80
        },
        my_ec2_02 = {
          target_id = module.ec2_complete[1].id
          port      = 80
        }
      }
      tags = local.tags
    }
  ]

  tags = local.tags

  lb_tags = local.tags

  target_group_tags = local.tags

  http_tcp_listeners_tags = local.tags
}
