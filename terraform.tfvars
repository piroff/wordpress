region = "eu-west-1"
name   = "wordpress"

vpc_cidr_block     = "192.168.0.0/24"
wp_instances       = "2"
ami_id             = "ami-09ce2fc392a4c0fbc"
instance_type      = "t2.micro"
ec2_ebs_size       = 8
rds_instance_class = "db.t2.small"
db_name            = "WPDB"
db_user            = "wpadmin"
