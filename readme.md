# VirtualCorp

VirtualCorp is a virtual networking lab for designing and deploying a branch office network. It uses MikroTik RouterOS CHR virtual machines on VirtualBox and automates their setup with shell scripts and Make.

Read the [full project statement](docs/statement.html) for the scenario, requirements, and detailed assignment.

## Getting started

### 1. Install prerequisites

Install GNU Make, VirtualBox with `VBoxManage`, `curl`, `unzip`, and the OpenSSH client. Make sure hardware virtualization is enabled on the host.

### 2. Adapt the environment

From the project root, create the local Make configuration and edit it for your machine:

```bash
cp .env.example .env
```

Update paths such as `PROJECT_ROOT`, `ARTIFACTS_DIR`, `CONFIGS_DIR`, and the SSH key directories as needed. The `.env` file uses GNU Make assignments and is ignored by Git.

### 3. Create the routers

Run `make` to display the available targets. Generate the SSH keys, then deploy the routers:

```bash
make ssh-keys
make deploy-routers
```

The deployment downloads the RouterOS CHR disk image when it is missing and creates `mikrotik0` through `mikrotik3` in VirtualBox.

### 4. Check the lab

Confirm that all four VMs appear in VirtualBox, under the `/VirtualCorp/Routers` group. Open each router's console and check that it can reach the other routers' transit addresses:

| Router | Transit address |
| --- | --- |
| `mikrotik0` | `10.7.0.225` |
| `mikrotik1` | `10.7.0.226` |
| `mikrotik2` | `10.7.0.230` |
| `mikrotik3` | `10.7.0.234` |

From each router, ping the other three addresses. For example:

```text
ping 10.7.0.226 count=4
```

Then check internet connectivity from each router:

```text
ping 1.1.1.1 count=4
```

The lab is ready when all four routers can reach one another and each can reach the internet.
