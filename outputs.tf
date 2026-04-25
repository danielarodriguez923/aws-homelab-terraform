output "bastion_public_ip" {
  description = "Bastion host public IP"
  value       = aws_instance.bastion.public_ip
}

output "windows_private_ip" {
  description = "Windows Server private IP"
  value       = aws_instance.windows.private_ip
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.homelab.id
}

output "s3_bucket_name" {
  description = "S3 log bucket name"
  value       = aws_s3_bucket.logs.bucket
}