
#ifdef __cplusplus
extern "C" {
#endif

I16 __stdcall AD_InstallSecret(U16 wCardNumber, U8 *MasterSecret, U16 DataLock);
I16 __stdcall AD_SetMasterSecret(U16 wCardNumber, U8 *MasterSecret);
I16 __stdcall AD_EncryptReadSegment(U16 wCardNumber, U8* data, U8* romid, U8* manid, U8* read_mac, U8* read_challenge);
I16 __stdcall AD_EncryptComputeEnc(U16 wCardNumber, U8* new_data, U8* romid, U8* manid, U8* read_mac, U8* challenge, U8* enc_data, U8* chk_mac);
I16 __stdcall AD_EncryptAuthWritePageEnc(U16 wCardNumber, U16 numBytesTot, U8* enc_data, U8* old_data, U8* romid, U8* manid, U8* chk_mac, U8* challenge, U16 DataLock);
I16 __stdcall AD_ReadInstallSecretStatus(U16 wCardNumber, U8* InstallBit, U8* LockDataBit);


#ifdef __cplusplus
}
#endif
