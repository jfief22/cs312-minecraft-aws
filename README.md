# Minecraft on AWS — Automated Deployment

Provisions and configures a Minecraft Java Edition server on AWS using Terraform and Ansible. The entire pipeline runs from a single command. No clicks in the AWS Management Console are required after credentials are configured.

This repository is the Part 2 deliverable for CS312 (Systems Administration) at Oregon State University. It builds on the manual Part 1 setup by replacing every console click with infrastructure-as-code.

## Background

The previous system administrator at Acme Corp configured the Minecraft server manually and left behind decent documentation, but two problems made the setup fragile. First, every change required logging into the AWS console and running shell commands by hand, which does not scale and cannot be reviewed. Second, the server did not shut down cleanly on reboot, which led to occasional world corruption.

This project addresses both. Terraform provisions all AWS resources from declarative configuration. Ansible installs Docker on the instance and configures a systemd unit that wraps the Minecraft container. The systemd unit sends a graceful `stop` command into the server console before the container is killed, so world data is flushed to disk on shutdown.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Operator workstation (Linux, macOS, or Windows with WSL)       │
│                                                                 │
│   ./deploy.sh                                                   │
│      │                                                          │
│      ├─► terraform apply ──► AWS (VPC, subnet, IGW, SG, EC2)    │
│      │                                                          │
│      ├─► poll TCP 22 until SSH is reachable                     │
│      │                                                          │
│      └─► ansible-playbook ──► EC2 instance                      │
│                                  │                              │
│                                  ├─► dnf install docker         │
│                                  ├─► docker pull minecraft img  │
│                                  ├─► install systemd unit       │
│                                  └─► systemctl enable + start   │
└─────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
                ┌─────────────────────────────────┐
                │  EC2 (Amazon Linux 2023)        │
                │  ┌───────────────────────────┐  │
                │  │ systemd: minecraft.service│  │
                │  │  └─ docker run ...        │  │
                │  │      └─ itzg/minecraft    │  │
                │  │          (port 25565)     │  │
                │  └───────────────────────────┘  │
                │  /opt/minecraft/data (world)    │
                └─────────────────────────────────┘
```

The pipeline runs in five stages:

1. **Terraform init** downloads the AWS, TLS, and local providers.
2. **Terraform apply** creates the VPC, public subnet, internet gateway, route table, security group, SSH key pair, and the EC2 instance. The private key is written to `minecraft-key.pem` at the repo root and the Ansible inventory file is rendered from a template using the instance's public IP.
3. **Wait for SSH** polls port 22 on the new instance until it responds.
4. **Ansible collection install** pulls the `community.docker` collection.
5. **Ansible playbook** installs Docker, pulls the Minecraft image, writes the systemd unit, and starts the service. The final task waits for port 25565 to open so the script does not exit until the server is actually accepting connections.

## Requirements

### Tools

| Tool | Version | Notes |
|------|---------|-------|
| Terraform | >= 1.5 | https://developer.hashicorp.com/terraform/install |
| Ansible | >= 2.14 | `pip install ansible` or system package manager |
| AWS CLI | >= 2.x | Not strictly required at runtime but useful for credential verification |
| nmap | any | For the verification step at the end |
| bash, nc | any | Used by `deploy.sh` |

### Windows users

Ansible does not run natively on Windows. Use **WSL** (Windows Subsystem for Linux) with Ubuntu 22.04 or later. Install the tools above inside WSL, then clone this repo into your WSL home directory and run `./deploy.sh` from there.

### AWS credentials

The Learner Lab issues temporary credentials that include a session token and expire every few hours. Before running `./deploy.sh`, retrieve fresh credentials from the Learner Lab module and export them:

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
export AWS_DEFAULT_REGION=us-east-1
```

Alternatively, paste them into `~/.aws/credentials` under a `[default]` profile, including the `aws_session_token` line.

You do **not** need to create an SSH key pair in AWS manually. Terraform generates one locally with the `tls` provider and uploads the public half.

## Quick Start

```bash
git clone <repo-url>
cd <repo-dir>

# Make sure AWS credentials are exported (see above)
./deploy.sh

# When deploy.sh finishes, verify with the command from the assignment prompt
nmap -sV -Pn -p T:25565 <public_ip>

# Connect with the Minecraft Java client:
#   Multiplayer -> Add Server -> Server Address: <public_ip>
```

When you are finished, tear everything down:

```bash
./destroy.sh
```

This destroys all AWS resources and removes the generated `minecraft-key.pem` and `ansible/inventory.ini`.

## Repository layout

```
.
├── deploy.sh                  # one-command deploy wrapper
├── destroy.sh                 # teardown wrapper
├── README.md                  # this file
├── .gitignore                 # excludes state files, keys, generated inventory
├── terraform/
│   ├── versions.tf            # provider versions
│   ├── variables.tf           # configurable inputs
│   ├── main.tf                # VPC, subnet, IGW, RT, SG, key pair, EC2
│   └── outputs.tf             # IPs, helper commands, inventory generation
└── ansible/
    ├── inventory.tmpl         # template populated by Terraform
    ├── playbook.yml           # install Docker, configure systemd
    └── files/
        └── minecraft.service  # systemd unit with graceful shutdown
```

## Configuration

All Terraform inputs have sensible defaults. To override, create `terraform/terraform.tfvars`:

```hcl
aws_region             = "us-west-2"
instance_type          = "t3.large"
ssh_allowed_cidr       = "203.0.113.42/32"  # restrict SSH to your home IP
minecraft_allowed_cidr = "0.0.0.0/0"
```

To change the Minecraft version, edit `ansible/files/minecraft.service` and add a `-e VERSION=1.20.4` line to the `ExecStart`. The `itzg/minecraft-server` image supports many additional environment variables documented at its GitHub page.

## Why this works around the assignment constraints

The assignment prohibits four things in the final demo:

- **No AWS Management Console.** Everything is Terraform and the AWS CLI under the hood. The only console visit is the Learner Lab module to copy credentials.
- **No manual connections to AWS resources.** Ansible connects over SSH but it is automated, not interactive. The operator never opens an SSH session by hand during the demo.
- **No SSH from the terminal.** Same as above. SSH is invoked by Ansible inside the script.
- **No `user_data` field.** The EC2 resource in `main.tf` deliberately omits `user_data`. All configuration runs through Ansible after the instance is up.

## How the clean shutdown works

The `minecraft.service` systemd unit defines an `ExecStop` directive:

```
ExecStop=/bin/sh -c '/usr/bin/docker exec minecraft rcon-cli stop || /usr/bin/docker stop -t 90 minecraft'
```

When the instance reboots or someone runs `systemctl stop minecraft`, systemd first runs `rcon-cli stop`, which sends the literal `stop` command to the Minecraft server console. The server saves all worlds, kicks players cleanly, and exits. If rcon-cli fails for any reason, the fallback `docker stop -t 90` sends SIGTERM and waits up to 90 seconds before forcing the container down. The `itzg/minecraft-server` image traps SIGTERM and triggers the same save-and-exit path internally.

`Restart=always` plus `WantedBy=multi-user.target` ensures the service comes back up automatically after a reboot.

## Verification

After `deploy.sh` finishes, the assignment requires verifying the server with nmap. The expected output looks like this:

```
$ nmap -sV -Pn -p T:25565 <public_ip>
Starting Nmap ...
PORT      STATE SERVICE   VERSION
25565/tcp open  minecraft Minecraft 1.21.x (Protocol: ...)
```

The `STATE open` and the `SERVICE minecraft` line confirm both that the port is reachable and that an actual Minecraft server is listening, not just an open TCP socket.

## Resources and sources

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) — Docker image used for the Minecraft server
- [Terraform AWS provider docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Ansible community.docker collection](https://docs.ansible.com/ansible/latest/collections/community/docker/)
- [systemd.service man page](https://www.freedesktop.org/software/systemd/man/systemd.service.html) — reference for `ExecStop` and `TimeoutStopSec`
- [Amazon Linux 2023 user guide](https://docs.aws.amazon.com/linux/al2023/ug/what-is-amazon-linux.html)
- CS312 course materials (Oregon State University) for the overall project structure and constraints

## Extra credit claimed

- **Docker image (+5 pts):** The Minecraft server runs as a container from the `itzg/minecraft-server` image rather than installing Java and the server jar directly on the host. This also enables the clean-shutdown behavior described above through the image's built-in signal handling.
