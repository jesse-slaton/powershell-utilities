$SystemDrive = $Env:SystemDrive
Enable-ComputerRestore -Drive $SystemDrive
vssadmin.exe resize ShadowStorage /For=$SystemDrive /On=$SystemDrive /MaxSize=10%