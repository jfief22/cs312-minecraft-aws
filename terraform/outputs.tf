output "instance_public_ip" {
  description = "Public IP of the Minecraft server. Use this with nmap and Minecraft client."
  value       = aws_instance.minecraft.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the Minecraft server."
  value       = aws_instance.minecraft.public_dns
}

output "ssh_command" {
  description = "SSH command for manual debugging (not used in demo)."
  value       = "ssh -i minecraft-key.pem ec2-user@${aws_instance.minecraft.public_ip}"
}

output "nmap_command" {
  description = "Verification command from the assignment prompt."
  value       = "nmap -sV -Pn -p T:25565 ${aws_instance.minecraft.public_ip}"
}

###############################################################################
# Generate the Ansible inventory automatically so deploy.sh can find the host
# without any manual editing between stages.
###############################################################################

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/../ansible/inventory.tmpl", {
    public_ip = aws_instance.minecraft.public_ip
  })
  filename = "${path.module}/../ansible/inventory.ini"
}
