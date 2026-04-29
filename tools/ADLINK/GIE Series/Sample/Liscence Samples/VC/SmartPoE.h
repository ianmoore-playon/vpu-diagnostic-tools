
#ifdef __cplusplus
extern "C" {
#endif

//DASK Data Types
typedef unsigned char   U8;
typedef short           I16;
typedef unsigned short  U16;
typedef long            I32;
typedef unsigned long   U32;
typedef float           F32;
typedef double          F64;

#define MAX_CARD        32

//Error Number
#define PoE_NoError                       0
#define PoE_ErrorInvalidCardNumber       -2
#define PoE_ErrorTooManyCardRegistered   -3
#define PoE_ErrorCardNotRegistered       -4
#define PoE_ErrorFuncNotSupport          -5
#define PoE_ErrorInvalidArgument         -11
#define PoE_ErrorOpenDriverFailed        -13
#define PoE_ErrorOverTemperature         -50
#define PoE_ErrorEncryptAuth             -70
#define ToE_ErrorInvalidIPaddress        -77

#define TRUE    1
#define FALSE   0


/*------------------------------------------------------------------
** Function prototype
------------------------------------------------------------------*/
I16 __stdcall SmartPoE_Register_Card (U16 card_num);
I16 __stdcall SmartPoE_Release_Card (U16 wCardNumber);
I16 __stdcall SmartPoE_Power_Enable(U16 wCardNumber, U16 wEnPort1, U16 wEnPort2, U16 wEnPort3, U16 wEnPort4 );  //0x86
I16 __stdcall SmartPoE_Get_Power_Enable(U16 wCardNumber, U16 *wEnPort1, U16 *wEnPort2, U16 *wEnPort3, U16 *wEnPort4 ); //0x96
I16 __stdcall SmartPoE_Get_ID(U16 wCardNumber, U16 *wPort );

I16 __stdcall SmartPoE_Get_DeviceInfo(U16 wCardNumber, U8 *wVersion, I32 size);
I16 __stdcall SmartPoE_Get_ProductName(U16 wCardNumber, I32 *productName);

///////////////////////////////////

I16 __stdcall SmartPoE_Get_Temperature(U16 wCardNumber, F64 *wTemperature );  
I16 __stdcall SmartPoE_Get_POEstate(U16 wCardNumber, U8 *bPOEstatePA0, U8 *bPOEstatePA1, U8 *bPOEstatePowerBudget, U8 *bPOEstatePA4, U8 *bPOEstatePA3, U8 *bPOEstatePF0 );  //0x81

I16 __stdcall SmartPoE_Get_POEPortLaststate(U16 wCardNumber, U16 *wPOEstate );  

I16 __stdcall SmartPoE_Get_HighTemperature(U16 wCardNumber, U16 *wHighTemperature );  
I16 __stdcall SmartPoE_Get_LowTemperature(U16 wCardNumber, U16 *wLowTemperature ); 
I16 __stdcall SmartPoE_Set_HighTemperature(U16 wCardNumber, U16 wHighTemperature ); 
I16 __stdcall SmartPoE_Set_LowTemperature(U16 wCardNumber, U16 wLowTemperature );  
I16 __stdcall SmartPoE_Get_PortStatus(U16 wCardNumber, U16 PortNumber, U8 *bstateClass, U8 *bstatePowerGood );  

I16 __stdcall SmartPoE_Get_PSEPortCurrent(U16 wCardNumber, U16 PortNumber, F64 *wCurrent );
I16 __stdcall SmartPoE_Get_PSEPortVoltage(U16 wCardNumber, U16 PortNumber, F64 *wVoltage );  
I16 __stdcall SmartPoE_Get_POEConsPowbudget(U16 wCardNumber, F64 *wPower );  
I16 __stdcall SmartPoE_Get_POELeftPowbudget(U16 wCardNumber, F64 *wPower ); 
I16 __stdcall SmartPoE_Get_PowerBudgetControl(U16 wCardNumber, U16 *wMode);  
I16 __stdcall SmartPoE_Set_PowerBudgetControl(U16 wCardNumber, U16 wMode);  
I16 __stdcall SmartPoE_Get_SmartFan(U16 wCardNumber, U8 *enable);
I16 __stdcall SmartPoE_Set_SmartFan(U16 wCardNumber, U8 enable);
I16 __stdcall SmartPoE_Get_FanSpeed(U16 wCardNumber, U16 *wRPM);

//Trigger Over Ethernet
I16 __stdcall GIE_Set_ActionCommand(U16 wCardNumber, U16 PortNumber, U32 gActionDeviceKey, U32 gActionGroupKey, U32 gActionGroupMask);
I16 __stdcall GIE_Get_ActionCommand(U16 wCardNumber, U16 PortNumber, U32 *gActionDeviceKey, U32 *gActionGroupKey, U32 *gActionGroupMask);
I16 __stdcall GIE_Send_SoftwareActionCommand(U16 wCardNumber, U16 PortNumber);
I16 __stdcall GIE_Send_AllSoftwareActionCommand(U16 wCardNumber);
I16 __stdcall GIE_GetTriggerMode(U16 wCardNumber, U16 *Mode);
I16 __stdcall GIE_SetTriggerMode(U16 wCardNumber, U16 Mode);
I16 __stdcall GIE_GetTriggerSource(U16 wCardNumber, U16 *Source);
I16 __stdcall GIE_SetTriggerSource(U16 wCardNumber, U16 Source);
I16 __stdcall GIE_GetTriggerActivation(U16 wCardNumber, U16 *Activation);
I16 __stdcall GIE_SetTriggerActivation(U16 wCardNumber, U16 Activation);
I16 __stdcall GIE_GetTriggerType(U16 wCardNumber, U16 *Type);
I16 __stdcall GIE_SetTriggerType(U16 wCardNumber, U16 Type);
I16 __stdcall GIE_GetTriggerDebounce(U16 wCardNumber, UINT *Debounce);
I16 __stdcall GIE_SetTriggerDebounce(U16 wCardNumber, U32 Debounce);
I16 __stdcall GIE_GetTriggerCount(U16 wCardNumber, U16 PortNumber, U16 *TriggerCount, U16 *TriggerSentCount);

I16 __stdcall GIE_ResetTriggerCount(U16 wCardNumber);


//Old functions, don't use the following function as far as possible
/////SmartPoE_Get_DeviceInfo() can replace the following functions
I16 __stdcall SmartPoE_Get_MCUVersion(U16 wCardNumber, U16 *wVersion );  
I16 __stdcall SmartPoE_Get_CPLDVersion(U16 wCardNumber, U32 *wVersion1, U32 *wVersion2 );
I16 __stdcall GIE_Get_Chk_EEVersion(U16 wCardNumber, U16 *wVersion );
I16 __stdcall GIE_Get_Chk_EEStandard(U16 wCardNumber, U16 *wStandard );
I16 __stdcall GIE_Get_Chk_EEPort(U16 wCardNumber, U16 *wPort );

#ifdef __cplusplus
}
#endif
