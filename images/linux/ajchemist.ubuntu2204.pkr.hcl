variable "vm_name" {
  type = string
  default = "ubuntu2204-runner"
}

variable "vmcx_path" {
  type = string
  default = ""
}

variable "cpus" {
  type = number
  default = 1
}

variable "memory" {
  type = number
  default = 1024
}

variable "ssh_username" {
  type = string
  default = "ubuntu"
}

variable "ssh_password" {
  type = string
  default = "ubuntu"
  sensitive = true
}

variable "ssh_timeout" {
  type = string
  default = "20m"
}

variable "ssh_handshake_attempts" {
  type = number
  default = 20
}

variable "boot_wait" {
  type = string
  default = "1s"
}

variable "shutdown_timeout" {
  type = string
  default = "50m"
}

variable "image_version" {
  type = string
  default = "dev"
}

variable "image_os" {
  type = string
  default = "ubuntu2204"
}

variable "image_folder" {
  type = string
  default = "/imagegeneration"
}

variable "imagedata_file" {
  type = string
  default = "/imagegeneration/imagedata.json"
}

variable "commit_file" {
  type = string
  default = "/imagegeneration/commit.txt"
}

variable "metadata_file" {
  type = string
  default = "/imagegeneration/metadatafile"
}

variable "installer_script_folder" {
  type = string
  default = "/imagegeneration/installers"
}

variable "helper_script_folder" {
  type = string
  default = "/imagegeneration/helpers"
}

variable "announcements" {
  type = string
  default = ""
}

variable "run_validation_diskspace" {
  type = bool
  default = false
}

locals {
  output_directory = "${path.root}/output/${var.vm_name}"
}

source "hyperv-vmcx" "vm" {
  vm_name = "${var.vm_name}"
  clone_from_vmcx_path = "${var.vmcx_path}"
  enable_secure_boot = true
  secure_boot_template = "MicrosoftUEFICertificateAuthority"
  guest_additions_mode = "enable"
  cpus = "${var.cpus}"
  memory = "${var.memory}"

  output_directory = "${local.output_directory}"

  communicator = "ssh"
  ssh_username = "${var.ssh_username}"
  ssh_password = "${var.ssh_password}"
  ssh_pty = true
  ssh_timeout = "${var.ssh_timeout}"
  ssh_handshake_attempts = "${var.ssh_handshake_attempts}"

  boot_wait = "${var.boot_wait}"

  shutdown_timeout = "${var.shutdown_timeout}"
  shutdown_command = "echo ${var.ssh_username} | sudo -S -E shutdown -P now"
}

build {
  sources = ["source.hyperv-vmcx.vm"]

  provisioner "shell" {
    inline = [
      "mkdir ${var.image_folder}",
      "chmod 777 ${var.image_folder}"
    ]
    execute_command = "sudo -S -E sh -c '{{ .Vars }} {{ .Path }}'"
  }

  # preparation
  provisioner "shell" {
    inline = [
      "apt-get -yq update",
      "touch /etc/waagent.conf" # prepare installers/configure-environment.sh
    ]
    execute_command = "sudo -S -E sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/scripts/base/apt-mock.sh"
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/base/repos.sh"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script           = "${path.root}/scripts/base/apt.sh"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/scripts/base/limits.sh"
  }

  provisioner "file" {
    source = "${path.root}/scripts/helpers"
    destination = "${var.helper_script_folder}"
  }

  provisioner "file" {
    source = "${path.root}/scripts/installers"
    destination = "${var.installer_script_folder}"
  }

  provisioner "file" {
    source = "${path.root}/post-generation"
    destination = "${var.image_folder}"
  }

  provisioner "file" {
    source = "${path.root}/scripts/tests"
    destination = "${var.image_folder}"
  }

  provisioner "file" {
    destination = "${var.image_folder}"
    source      = "${path.root}/scripts/SoftwareReport"
  }

  provisioner "file" {
    source = "${path.root}/toolsets/toolset-2204.json"
    destination = "${var.installer_script_folder}/toolset.json"
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGEDATA_FILE=${var.imagedata_file}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/preimagedata.sh"]
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${var.image_os}", "HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/configure-environment.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/complete-snap-setup.sh", "${path.root}/scripts/installers/powershellcore.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/Install-PowerShellModules.ps1"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/docker-compose.sh", "${path.root}/scripts/installers/docker-moby.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "${path.root}/scripts/installers/azure-cli.sh",
      "${path.root}/scripts/installers/azure-devops-cli.sh",
      "${path.root}/scripts/installers/basic.sh",
      "${path.root}/scripts/installers/aws.sh",
      "${path.root}/scripts/installers/clang.sh",
      "${path.root}/scripts/installers/cmake.sh",
      "${path.root}/scripts/installers/git.sh",
      "${path.root}/scripts/installers/github-cli.sh",
      "${path.root}/scripts/installers/heroku.sh",
      "${path.root}/scripts/installers/java-tools.sh",
      "${path.root}/scripts/installers/nvm.sh",
      "${path.root}/scripts/installers/nodejs.sh",
      "${path.root}/scripts/installers/packer.sh"
    ]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/scripts/base/snap.sh"
  }

  provisioner "shell" {
    execute_command   = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    scripts           = ["${path.root}/scripts/base/reboot.sh"]
  }

  provisioner "shell" {
    inline = [
      "usermod -aG docker ${var.ssh_username}",
      "mkdir -p $HOME/.docker",
      "chown -R ${var.ssh_username}.${var.ssh_username} $HOME/.docker"
    ]
    execute_command = "sudo -S -E sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    pause_before        = "1m0s"
    scripts             = ["${path.root}/scripts/installers/cleanup.sh"]
    start_retry_timeout = "10m"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/scripts/base/apt-mock-remove.sh"
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPT_FOLDER=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "IMAGE_FOLDER=${var.image_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/post-deployment.sh"]
  }

  provisioner "shell" {
    environment_vars = ["RUN_VALIDATION=${var.run_validation_diskspace}"]
    scripts          = ["${path.root}/scripts/installers/validate-disk-space.sh"]
  }
}
