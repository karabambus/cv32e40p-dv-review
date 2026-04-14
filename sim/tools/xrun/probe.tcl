set wavefile  waves.shm
database -open $wavefile -shm

probe -create -shm uvmt_cv32e40p_tb.dut_wrap -all -depth all -shm -database $wavefile
probe -create -shm uvmt_cv32e40p_tb.imperas_dv -all -depth all -shm -database $wavefile
run 
exit
