using System;
using System.Runtime.InteropServices;

/// <summary>
/// SmartPoE class library
/// </summary>
public class SmartPoE
{
    public const ushort MAX_CARD = 32;

    #region Error Number
    public const short PoE_NoError = 0;
    public const short PoE_ErrorInvalidCardNumber = -2;
    public const short PoE_ErrorTooManyCardRegistered = -3;
    public const short PoE_ErrorCardNotRegistered = -4;
    public const short PoE_ErrorFuncNotSupport = -5;
    public const short PoE_ErrorInvalidArgument = -11;
    public const short PoE_ErrorInvalidSecret = -12;
    public const short PoE_ErrorOpenDriverFailed = -13;
    public const short PoE_ErrorLockSecret = -15;
    public const short PoE_ErrorOverTemperature = -50;
    public const short PoE_ErrorEncryptAuth = -70;
    public const short ToE_ErrorInvalidIPaddress = -77;
    #endregion


    //Error Number
    public const string SmartPoE_DLL_FILE_NAME = "SmartPoE.dll";

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Register_Card(ushort card_num);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Release_Card(ushort wCardNumber);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_Power_Enable(ushort wCardNumber, out ushort wEnPort1, out ushort wEnPort2, out ushort wEnPort3, out ushort wEnPort4);  //

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Power_Enable(ushort wCardNumber, ushort wEnPort1, ushort wEnPort2, ushort wEnPort3, ushort wEnPort4);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_ID(ushort wCardNumber, out ushort wPort);
	
	[DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_DeviceInfo(ushort wCardNumber, byte [] wPort, int size);
	
	[DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_ProductName(ushort wCardNumber, out int productName);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_Temperature(ushort wCardNumber, out double wTemperature);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_POEstate(ushort wCardNumber, out byte bPOEstatePA0, out byte bPOEstatePA1, out byte bPOEstatePowerBudget, out byte bPOEstatePA4, out byte bPOEstatePA3, out byte bPOEstatePF0);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_POEPortLaststate(ushort wCardNumber, out short wPOEPortLaststate);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_HighTemperature(ushort wCardNumber, out short wHighTemperature);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_LowTemperature(ushort wCardNumber, out short wLowTemperature);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Set_HighTemperature(ushort wCardNumber, short wHighTemperature);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Set_LowTemperature(ushort wCardNumber, short wLowTemperature);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_PortStatus(ushort wCardNumber, short PortNumber, out byte bstateClass, out byte bstatePowerGood);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_PSEPortCurrent(ushort wCardNumber, short PortNumber, out double wCurrent);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_PSEPortVoltage(ushort wCardNumber, short PortNumber, out double wVoltage);
	
    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_POEConsPowbudget(ushort wCardNumber, out double wPower);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_POELeftPowbudget(ushort wCardNumber, out double wPower);
	
    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_PowerBudgetControl(ushort wCardNumber, out short wMode);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Set_PowerBudgetControl(ushort wCardNumber, short wMode);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_SmartFan(ushort wCardNumber, out byte enable);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Set_SmartFan(ushort wCardNumber, byte enable);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_FanSpeed(ushort wCardNumber,out ushort RPM);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_Set_ActionCommand(ushort wCardNumber, ushort PortNumber, uint gActionDeviceKey, uint gActionGroupKey, uint gActionGroupMask);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_Get_ActionCommand(ushort wCardNumber, ushort PortNumber, out uint gActionDeviceKey, out uint gActionGroupKey, out uint gActionGroupMask);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_Send_SoftwareActionCommand(ushort wCardNumber, ushort PortNumber);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_Send_AllSoftwareActionCommand(ushort wCardNumber);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_GetTriggerMode(ushort wCardNumber, out ushort Mode);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_SetTriggerMode(ushort wCardNumber, ushort Mode);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_GetTriggerSource(ushort wCardNumber, out ushort Source);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_SetTriggerSource(ushort wCardNumber, ushort Source);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_GetTriggerActivation(ushort wCardNumber, out ushort Activation);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_SetTriggerActivation(ushort wCardNumber, ushort Activation);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_GetTriggerType(ushort wCardNumber, out ushort Type);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_SetTriggerType(ushort wCardNumber, ushort Type);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_GetTriggerDebounce(ushort wCardNumber, out uint Debounce);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_SetTriggerDebounce(ushort wCardNumber, uint Debounce);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_GetTriggerCount(ushort wCardNumber, ushort PortNumber, out ushort TriggerCount, out ushort TriggerSentCount);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_ResetTriggerCount(ushort wCardNumber);

    //Old functions, don't use the following function as far as possible
    ////SmartPoE_Get_DeviceInfo() can replace the following functions
    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_CPLDVersion(ushort wCardNumber, out uint wVersion1, out uint wVersion2);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short SmartPoE_Get_MCUVersion(ushort wCardNumber, out ushort wVersion);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_Get_Chk_EEVersion(ushort wCardNumber, out short wVersion);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_Get_Chk_EEStandard(ushort wCardNumber, out short wStandard);

    [DllImport(SmartPoE_DLL_FILE_NAME)]
    public static extern short GIE_Get_Chk_EEPort(ushort wCardNumber, out short wPort);
}
