set partNumber $::env(XILINX_PART)
set boardName  $::env(XILINX_BOARD)
set ipName xlnx_axi_hwicap
create_project $ipName . -force -part $partNumber
set_property board_part $boardName [current_project]
create_ip -name axi_hwicap -vendor xilinx.com -library ip \
    -version 3.0 -module_name $ipName
set_property -dict [list \
    CONFIG.C_ICAP_EXTERNAL   {0} \
    CONFIG.C_DEVICE_ID       {0x03647093} \
    CONFIG.C_OPERATION       {1} \
    CONFIG.C_INCLUDE_STARTUP {1} \
] [get_ips $ipName]
generate_target {instantiation_template} \
    [get_files ./$ipName.srcs/sources_1/ip/$ipName/$ipName.xci]
generate_target all \
    [get_files ./$ipName.srcs/sources_1/ip/$ipName/$ipName.xci]
create_ip_run \
    [get_files -of_objects [get_fileset sources_1] \
    ./$ipName.srcs/sources_1/ip/$ipName/$ipName.xci]
launch_run -jobs 8 ${ipName}_synth_1
