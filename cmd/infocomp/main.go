package main

import (
	_ "embed"
)

//go:embed winrm-ps/info_basic.ps1
var ps1_info_basic string

//go:embed winrm-ps/info_gpo.ps1
var ps1_info_gpo string

//go:embed winrm-ps/info_hardware.ps1
var ps1_info_hardware string

//go:embed winrm-ps/info_network.ps1
var ps1_info_network string

//go:embed winrm-ps/info_realtime.ps1
var ps1_info_realtime string

//go:embed winrm-ps/info_system.ps1
var ps1_info_system string

func main() {

}
