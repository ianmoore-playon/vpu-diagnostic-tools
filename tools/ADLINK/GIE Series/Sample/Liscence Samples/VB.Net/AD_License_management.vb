Imports System.Collections.Generic
Imports System.Linq
Imports System.Text
Imports System.Threading.Tasks
Imports System.Runtime.InteropServices


Class AD_License_management
	<DllImport("SmartPoE.dll", EntryPoint := "AD_InstallSecret")> _
	Public Shared Function AD_InstallSecret(wCardNumber As UShort, MasterSecret As Byte(), LockBit As Boolean) As Short
	End Function

	<DllImport("SmartPoE.dll", EntryPoint := "AD_SetMasterSecret")> _
	Public Shared Function AD_SetMasterSecret(wCardNumber As UShort, MasterSecret As Byte()) As Short
	End Function


	<DllImport("SmartPoE.dll", EntryPoint := "AD_EncryptReadSegment")> _
	Public Shared Function AD_EncryptReadSegment(wCardNumber As UShort, data As Byte(), romid As Byte(), manid As Byte(), read_mac As Byte(), read_challenge As Byte()) As Short
	End Function

	<DllImport("SmartPoE.dll", EntryPoint := "AD_EncryptComputeEnc")> _
	Public Shared Function AD_EncryptComputeEnc(wCardNumber As UShort, new_data As Byte(), romid As Byte(), manid As Byte(), read_mac As Byte(), challenge As Byte(), _
		enc_data As Byte(), chk_mac As Byte()) As Short
	End Function

	<DllImport("SmartPoE.dll", EntryPoint := "AD_EncryptAuthWritePageEnc")> _
	Public Shared Function AD_EncryptAuthWritePageEnc(wCardNumber As UShort, numBytesTot As UShort, enc_data As Byte(), old_data As Byte(), romid As Byte(), manid As Byte(), _
		chk_mac As Byte(), challenge As Byte(), lockdata As UShort) As Short
    End Function

    <DllImport("SmartPoE.dll", EntryPoint:="AD_ReadInstallSecretStatus")> _
    Public Shared Function AD_ReadInstallSecretStatus(ByVal wCardNumber As UShort, ByRef InstallBit As Byte, ByRef LockBit As Byte) As Short
    End Function

End Class
