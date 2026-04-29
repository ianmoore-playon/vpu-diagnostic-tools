Imports Microsoft.VisualBasic
Imports System.Runtime.InteropServices

Module SmartPoE

    Public Const MAX_CARD As UShort = 32
    Public Const PoE_NoError As Short = 0
    Public Const PoE_ErrorInvalidCardNumber As Short = -2
    Public Const PoE_ErrorTooManyCardRegistered As Short = -3
    Public Const PoE_ErrorCardNotRegistered As Short = -4
    Public Const PoE_ErrorFuncNotSupport As Short = -5
    Public Const PoE_ErrorInvalidArgument As Short = -11
    Public Const PoE_ErrorInvalidSecret As Short = -12
    Public Const PoE_ErrorOpenDriverFailed As Short = -13
    Public Const PoE_ErrorLockSecret As Short = -15
    Public Const PoE_ErrorOverTemperature As Short = -50
    Public Const PoE_ErrorEncryptAuth As Short = -70
    Public Const ToE_ErrorInvalidIPaddress As Short = -77



    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Register_Card")> _
    Public Function Register_Card(ByVal wcard_num As UShort) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Release_Card")> _
    Public Function Release_Card(ByVal wCardNumber As UShort) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Power_Enable")> _
    Public Function Power_Enable(ByVal wCardNumber As UShort, ByVal wEnPort1 As UShort, ByVal wEnPort2 As UShort, ByVal wEnPort3 As UShort, ByVal wEnPort4 As UShort) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_Power_Enable")> _
    Public Function Get_Power_Enable(ByVal wCardNumber As UShort, ByRef wEnPort1 As UShort, ByRef wEnPort2 As UShort, ByRef wEnPort3 As UShort, ByRef wEnPort4 As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_ID")> _
    Public Function Get_ID(ByVal wCardNumber As UShort, ByRef wID As UShort) As Short
    End Function
	<DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_DeviceInfo")> _
    Public Function Get_DeviceInfo(ByVal wCardNumber As UShort, ByVal wVersion As IntPtr, ByVal size As UInteger) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_ProductName")> _
    Public Function Get_ProductName(ByVal wCardNumber As UShort, ByRef productName As Integer) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_Temperature")> _
    Public Function Get_Temperature(ByVal wCardNumber As UShort, ByRef wTemperature As Double) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_POEstate")> _
    Public Function Get_POEstate(ByVal wCardNumber As UShort, ByRef bPOEstatePA0 As Byte, ByRef bPOEstatePA1 As Byte, ByRef bPOEstatePowerBudget As Byte, ByRef bPOEstatePA4 As Byte, ByRef bPOEstatePA3 As Byte, ByRef bPOEstatePF0 As Byte) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_POEPortLaststate")> _
    Public Function Get_POEPortLaststate(ByVal wCardNumber As UShort, ByRef wPOEPortLaststate As Short) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_HighTemperature")> _
    Public Function Get_HighTemperature(ByVal wCardNumber As UShort, ByRef wHighTemperature As Short) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_LowTemperature")> _
    Public Function Get_LowTemperature(ByVal wCardNumber As UShort, ByRef wLowTemperature As Short) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Set_HighTemperature")> _
    Public Function Set_HighTemperature(ByVal wCardNumber As UShort, ByVal wHighTemperature As Short) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Set_LowTemperature")> _
    Public Function Set_LowTemperature(ByVal wCardNumber As UShort, ByVal wLowTemperature As Short) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_PortStatus")> _
    Public Function Get_PortStatus(ByVal wCardNumber As UShort, ByVal PortNumber As Short, ByRef bstateClass As Byte, ByRef bstatePowerGood As Byte) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_PSEPortCurrent")> _
    Public Function Get_PSEPortCurrent(ByVal wCardNumber As UShort, ByVal PortNumber As Short, ByRef wCurrent As Double) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_PSEPortVoltage")> _
    Public Function Get_PSEPortVoltage(ByVal wCardNumber As UShort, ByVal PortNumber As Short, ByRef wVoltage As Double) As Short
    End Function
	<DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_POEConsPowbudget")> _
    Public Function Get_POEConsPowbudget(ByVal wCardNumber As UShort, ByRef wPower As Double) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_POELeftPowbudget")> _
    Public Function Get_POELeftPowbudget(ByVal wCardNumber As UShort, ByRef wPower As Double) As Short
    End Function
	<DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_PowerBudgetControl")> _
    Public Function Get_PowerBudgetControl(ByVal wCardNumber As UShort, ByRef wMode As Short) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Set_PowerBudgetControl")> _
    Public Function Set_PowerBudgetControl(ByVal wCardNumber As UShort, ByVal wMode As Short) As Short
    End Function	
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_SmartFan")> _
    Public Function Get_SmartFan(ByVal wCardNumber As UShort, ByRef enable As Byte) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Set_SmartFan")> _
    Public Function Set_SmartFan(ByVal wCardNumber As UShort, ByVal enable As Byte) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_FanSpeed")> _
    Public Function Get_FanSpeed(ByVal wCardNumber As UShort, ByRef RPM As UShort) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_Set_ActionCommand")> _
    Public Function Set_ActionCommand(ByVal wCardNumber As UShort, ByVal PortNumber As UShort, ByVal gActionDeviceKey As UInteger, ByVal gActionGroupKey As UInteger, ByVal gActionGroupMask As UInteger) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_Get_ActionCommand")> _
    Public Function Get_ActionCommand(ByVal wCardNumber As UShort, ByVal PortNumber As UShort, ByRef gActionDeviceKey As UInteger, ByRef gActionGroupKey As UInteger, ByRef gActionGroupMask As UInteger) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_Send_SoftwareActionCommand")> _
    Public Function Send_SoftwareActionCommand(ByVal wCardNumber As UShort, ByVal PortNumber As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_Send_AllSoftwareActionCommand")> _
    Public Function Send_AllSoftwareActionCommand(ByVal wCardNumber As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_GetTriggerMode")> _
    Public Function GetTriggerMode(ByVal wCardNumber As UShort, ByRef Mode As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_SetTriggerMode")> _
    Public Function SetTriggerMode(ByVal wCardNumber As UShort, ByVal Mode As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_GetTriggerSource")> _
    Public Function GetTriggerSource(ByVal wCardNumber As UShort, ByRef Source As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_SetTriggerSource")> _
    Public Function SetTriggerSource(ByVal wCardNumber As UShort, ByVal Source As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_GetTriggerActivation")> _
    Public Function GetTriggerActivation(ByVal wCardNumber As UShort, ByRef Activation As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_SetTriggerActivation")> _
    Public Function SetTriggerActivation(ByVal wCardNumber As UShort, ByVal Activation As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_GetTriggerType")> _
    Public Function GetTriggerType(ByVal wCardNumber As UShort, ByRef Type As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_SetTriggerType")> _
    Public Function SetTriggerType(ByVal wCardNumber As UShort, ByVal Type As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_GetTriggerDebounce")> _
    Public Function GetTriggerDebounce(ByVal wCardNumber As UShort, ByRef Debounce As UInteger) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_SetTriggerDebounce")> _
    Public Function SetTriggerDebounce(ByVal wCardNumber As UShort, ByVal Debounce As UInteger) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_GetTriggerCount")> _
    Public Function GetTriggerCount(ByVal wCardNumber As UShort, ByVal PortNumber As UShort, ByRef TriggerCount As UShort, ByRef TriggerSentCount As UShort) As Integer
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_ResetTriggerCount")> _
    Public Function ResetTriggerCount(ByVal wCardNumber As UShort) As Integer
    End Function
    'Old functions, don't use the following function as far as possible
    '   SmartPoE_Get_DeviceInfo() can replace the following functions
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_MCUVersion")> _
    Public Function Get_MCUVersion(ByVal wCardNumber As UShort, ByRef wVersion As UShort) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="SmartPoE_Get_CPLDVersion")> _
    Public Function Get_CPLDVersion(ByVal wCardNumber As UShort, ByRef wVersion1 As UInteger, ByRef wVersion2 As UInteger) As Short
    End Function
	<DllImport("SmartPoE.dll", EntryPoint:="GIE_Get_Chk_EEVersion")> _
    Public Function Get_Chk_EEVersion(ByVal wCardNumber As UShort, ByRef wVersion As Short) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_Get_Chk_EEStandard")> _
    Public Function Get_Chk_EEStandard(ByVal wCardNumber As UShort, ByRef wStandard As Short) As Short
    End Function
    <DllImport("SmartPoE.dll", EntryPoint:="GIE_Get_Chk_EEPort")> _
    Public Function Get_Chk_EEPort(ByVal wCardNumber As UShort, ByRef wPort As Short) As Short
    End Function
End Module
