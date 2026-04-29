// SamrtPoESampleDlg.cpp : implementation file
//
#include <stdio.h>
#include <stdafx.h>
#include <conio.h>
#include <windows.h>
#include <shlobj.h>

#include "SamrtPoESample.h"
#include "SamrtPoESampleDlg.h"
#include "SmartPoE.h"
#include "AD_License_management.h"

#pragma comment(lib, "shell32.lib")

#ifdef _DEBUG
#define new DEBUG_NEW
#endif

FILE *DFile;

#define TRUE 1
#define FALSE 0

int dprintf(char *format, ...)
{
   int rt;
   va_list ap;

   if (DFile != NULL)
   {
      va_start(ap, format);
      rt = vfprintf(DFile,format,ap); 
      va_end(ap);

      fflush(DFile);
   }

   va_start(ap, format);
   rt = vfprintf(stdout,format,ap); 
   va_end(ap);

   return rt;
}

//////////////////////////////

CSamrtPoESampleDlg::CSamrtPoESampleDlg(CWnd* pParent /*=NULL*/)
	: CDialog(CSamrtPoESampleDlg::IDD, pParent),
    m_Number (-1)
{
	m_hIcon = AfxGetApp()->LoadIcon(IDR_MAINFRAME);
	m_nTimer = -1;
}

void CSamrtPoESampleDlg::DoDataExchange(CDataExchange* pDX)
{
	CDialog::DoDataExchange(pDX);
}

BEGIN_MESSAGE_MAP(CSamrtPoESampleDlg, CDialog)
	ON_WM_PAINT()
	ON_WM_QUERYDRAGICON()
	ON_WM_TIMER()
    ON_CBN_SELCHANGE(IDC_COMBO_CARD_NUMBER, &CSamrtPoESampleDlg::OnCbnSelchangeComboCardNumber)
    ON_WM_DESTROY()
	ON_BN_CLICKED(IDC_BUTTON_SET4, &CSamrtPoESampleDlg::OnBnClickedButtonSet4)
	ON_BN_CLICKED(IDC_BUTTON_SET27, &CSamrtPoESampleDlg::OnBnClickedButtonSet27)
	ON_BN_CLICKED(IDC_BUTTON_SET28, &CSamrtPoESampleDlg::OnBnClickedButtonSet28)
	ON_BN_CLICKED(IDC_BUTTON_SET29, &CSamrtPoESampleDlg::OnBnClickedButtonSet29)
	ON_BN_CLICKED(IDC_BUTTON_SET30, &CSamrtPoESampleDlg::OnBnClickedButtonSet30)
	ON_BN_CLICKED(IDC_BUTTON_SET31, &CSamrtPoESampleDlg::OnBnClickedButtonSet31)
	ON_BN_CLICKED(IDC_BUTTON_SET32, &CSamrtPoESampleDlg::OnBnClickedButtonSet32)
	ON_BN_CLICKED(IDC_BUTTON_SET33, &CSamrtPoESampleDlg::OnBnClickedButtonSet33)
END_MESSAGE_MAP()


UINT CSamrtPoESampleDlg::hex2uint(CString h)
{
	int len;
	LPSTR str;
	UINT ret = 0;
	char c;

	len = h.GetLength();
	if(len>16 || len<=0)
	{
		return 0;
	}

	h.MakeUpper();
	str = h.GetBuffer(10);

	for(int i=0;i<len;i++)
	{
		c = (char)str[i];
		if(c>='0' && c<='9') {
			ret = (ret << 4) + c - '0';
		}
		else if(c>='A' && c<='F') {
			ret = (ret << 4) + c - 'A' + 10;
		}
		else {
			return 0;
		}
	}

	return ret;
}

BOOL CSamrtPoESampleDlg::OnInitDialog()
{
	CDialog::OnInitDialog();

	// Set the icon for this dialog.  The framework does this automatically
	//  when the application's main window is not a dialog
	SetIcon(m_hIcon, TRUE);			// Set big icon
	SetIcon(m_hIcon, FALSE);		// Set small icon

    U16 i;
    //CString str;
    SHORT num;

    char txt[16];
	CString str,str2;

    for(i = 0; i < MAX_CARD; i++)
    {
        if((num = SmartPoE_Register_Card(i)) != PoE_NoError)
            break;

        SmartPoE_Release_Card((U16)num);

        str.Format("%d", i);
        ((CComboBox*)GetDlgItem(IDC_COMBO_CARD_NUMBER))->AddString(str);
    }

    if(i == 0)
    {
        MessageBox("No card is found!");
        exit(0);
    }

    ((CComboBox*)GetDlgItem(IDC_COMBO_CARD_NUMBER))->SetCurSel(0);

    OnCbnSelchangeComboCardNumber();


    SetDlgItemText(IDC_EDIT_DCSET4, "00");

    SetDlgItemText(IDC_EDIT_DCSET0, "55");

	_itoa_s(0, txt, sizeof(txt), 10);
    SetDlgItemText(IDC_EDIT_DCSET1, txt);

	_itoa_s(4, txt, sizeof(txt), 10);
    SetDlgItemText(IDC_EDIT_DCSET2, txt);

	_itoa_s(10, txt, sizeof(txt), 10);
    SetDlgItemText(IDC_EDIT_DCSET3, txt);



	for (i=0;i<32;i++)
	{
		str2.Format("%x", i);
		SetDlgItemText(IDC_EDIT_DCSETBUF0+i, str2);
	
	}


    SetDlgItemText(IDC_EDIT_DCGETBUF0, "00000000000000000000000000000000");


    SetDlgItemText(IDC_EDIT_DCGETBUF0, "00000000000000000000000000000000");

    SetDlgItemText(IDC_EDIT_DCGETBUF3, "0");

	((CButton*)GetDlgItem(IDC_RADIO1_OFF1))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF2))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF3))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF4))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF5))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF6))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF7))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF8))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF9))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF10))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF11))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF12))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF13))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF14))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF15))->SetCheck(1);
	((CButton*)GetDlgItem(IDC_RADIO1_OFF16))->SetCheck(1);

	((CButton*)GetDlgItem(IDC_RADIO1_ON1))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON2))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON3))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON4))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON5))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON6))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON7))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON8))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON9))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON10))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON11))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON12))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON13))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON14))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON15))->SetCheck(0);
	((CButton*)GetDlgItem(IDC_RADIO1_ON16))->SetCheck(0);


	return TRUE;  // return TRUE  unless you set the focus to a control
}

// If you add a minimize button to your dialog, you will need the code below
//  to draw the icon.  For MFC applications using the document/view model,
//  this is automatically done for you by the framework.

void CSamrtPoESampleDlg::OnPaint()
{
	if (IsIconic())
	{
		CPaintDC dc(this); // device context for painting

		SendMessage(WM_ICONERASEBKGND, reinterpret_cast<WPARAM>(dc.GetSafeHdc()), 0);

		// Center icon in client rectangle
		int cxIcon = GetSystemMetrics(SM_CXICON);
		int cyIcon = GetSystemMetrics(SM_CYICON);
		CRect rect;
		GetClientRect(&rect);
		int x = (rect.Width() - cxIcon + 1) / 2;
		int y = (rect.Height() - cyIcon + 1) / 2;

		// Draw the icon
		dc.DrawIcon(x, y, m_hIcon);
	}
	else
	{
		CDialog::OnPaint();
	}
}

// The system calls this function to obtain the cursor to display while the user drags
//  the minimized window.
HCURSOR CSamrtPoESampleDlg::OnQueryDragIcon()
{
	return static_cast<HCURSOR>(m_hIcon);
}

void CSamrtPoESampleDlg::OnCbnSelchangeComboCardNumber()
{
    I16 Number;
    U16 card_num = (U16)((CComboBox*)GetDlgItem(IDC_COMBO_CARD_NUMBER))->GetCurSel();


    if(m_Number >= 0)
        SmartPoE_Release_Card(m_Number);

    if((Number = SmartPoE_Register_Card(card_num)) != PoE_NoError)
    {
        MessageBox("Selecting card is failed");
        return;
    }

    U16 ID;
    I16 ret = SmartPoE_Get_ID((U16)Number, &ID);
    if(ret < 0)
        SetDlgItemText(IDC_EDIT_ERROR, "Error");
    else
    {
        char txt[16];
        _itoa_s(ID, txt, sizeof(txt), 10);
        SetDlgItemText(IDC_EDIT_ID, txt);
    }
    
    m_Number = Number;

/////////////////////////////

    ret = GIE_Get_Chk_EEVersion((U16)Number, &ID);
    if(ret < 0)
        SetDlgItemText(IDC_EDIT_ERROR, "Error");
    else
    {
        char txt[16];
        _itoa_s(ID, txt, sizeof(txt), 10);
        SetDlgItemText(IDC_EDIT_ID14, txt);
    }

    ret = GIE_Get_Chk_EEStandard((U16)Number, &ID);
    if(ret < 0)
        SetDlgItemText(IDC_EDIT_ERROR, "Error");
    else
    {
        char txt[16];
        _itoa_s(ID, txt, sizeof(txt), 10);
        SetDlgItemText(IDC_EDIT_ID15, txt);
    }

    ret = GIE_Get_Chk_EEPort((U16)Number, &ID);
    if(ret < 0)
        SetDlgItemText(IDC_EDIT_ERROR, "Error");
    else
    {
        char txt[16];
        _itoa_s(ID, txt, sizeof(txt), 10);
        SetDlgItemText(IDC_EDIT_ID16, txt);
    }

 	U32 ID2,ID3;

    ret = SmartPoE_Get_CPLDVersion((U16)Number, &ID2, &ID3);
    if(ret < 0)
        SetDlgItemText(IDC_EDIT_ERROR, "Error");
    else
    {
		CString str,str2;
		str.Format("%x", ID2 );
		str2.Format("%x", ID3 );
        SetDlgItemText(IDC_EDIT_ID18, str);
        SetDlgItemText(IDC_EDIT_ID19, str2);
    }

	//IDC_EDIT_ID18
	U16 MCUID; 

	ret = SmartPoE_Get_MCUVersion((U16)Number, &MCUID);
    if(ret < 0)
        SetDlgItemText(IDC_EDIT_ID20, "Error");
    else
    {
        CString str;
		str.Format("%x", MCUID );
        SetDlgItemText(IDC_EDIT_ID20, str);
    }


/////////////////////////////
	

}

void CSamrtPoESampleDlg::OnDestroy()
{
    CDialog::OnDestroy();

	if( m_nTimer != -1 )
	{
		KillTimer( m_nTimer );
		m_nTimer = -1;
	}

    if(m_Number >= 0)
        SmartPoE_Release_Card(m_Number);
}


void CSamrtPoESampleDlg::OnBnClickedButtonSet4()
{
	SetDlgItemText(IDC_EDIT_ERROR, "");

}

void CSamrtPoESampleDlg::OnBnClickedButtonSet27()
{
	// TODO: 北兜矪瞶盽Α祘Α絏

	U16 wCardNum = m_Number;

	U8 challenge[32];
	U8 data[32], new_data[32], data1[32]; 
	U8 mac[32];

	U8 page7SavedData[32], page8SavedData[32], page9SavedData[32];

	int result;
	int compareOK = 1;
	U16 startPage = 0x01;     
	int num_pages_to_test = 1;
	int num_bytes_to_test = 32;

	////////////////////////////

	U8 notUsed[1] = {0};
	U16 zeroLen = 0;
	U16 len32= 32;

	U8 data3[32];
	U8 data4[12];
	U8 data5[1];
	int i,rslt,rt = TRUE;
	int block,skip_setup=FALSE,page,cnt;

	U8 partial[32], new_page[32];
	int current_secret=0,cleared_byte;
	U8 memimage[512]; 
	U8 master_secret[32];
	U8 binding[32];
	U8 romid[8];
	U8 manid[2];

	UCHAR   ITROMId[8];
	UCHAR   ITMANId[2];
	UCHAR   ITmaster_secret[32];
	UCHAR   ITpartial[32];
	UCHAR   ITbinding[32];

	CString strHex;

	// open log file and print time stamp
	CHAR logfile[MAX_PATH];
	CHAR my_documents[MAX_PATH];
    result = SHGetFolderPath(NULL, CSIDL_PERSONAL, NULL, SHGFP_TYPE_CURRENT, my_documents);
	if (result == S_OK)
	{
		sprintf(my_documents, "%s\\ADLINK", my_documents);
		if (CreateDirectory(my_documents, NULL) || ERROR_ALREADY_EXISTS == GetLastError())
		{
		sprintf(logfile,"%s\\log6-0.txt",my_documents);
		DFile = fopen(logfile,"a+");
	}
	}

	if(DFile == NULL)
	{
		printf("ERROR, Could not open LOT.TXT log file!\n");
		exit(1);
	}

	srand((unsigned)time(NULL));

	for (i=0;i<32;i++)
	{
		GetDlgItemText(IDC_EDIT_DCSETBUF0+i, strHex);
		master_secret[i]=(U8)hex2uint(strHex);
	}

	dprintf("master_secret: ");
	for (i = 0; i < 32; i++)
	dprintf("%02X",master_secret[i]);
	dprintf("\n");

	//MessageBox("The Card will InstallSecret!!!");
	if(MessageBox("The Card will InstallSecret!!!", "InstallSecret",  MB_OKCANCEL) == IDOK)
	{
		dprintf("AD_SetMasterSecret, wCardNum %d\n",wCardNum);
		rslt = AD_InstallSecret(wCardNum, master_secret, false);

		dprintf(" %s\n",(rslt) ?  "FAIL" : "SUCCESS"); 
		if (rslt) rt = FALSE;

		if (rt == TRUE)
		{
			dprintf("Test Pass!");
		}
		else
		{
			dprintf("Test Fail!");   
		}
	}
	else
	{
		dprintf("Test Cancel");   	
	}
	fclose(DFile);
}

void CSamrtPoESampleDlg::OnBnClickedButtonSet28()
{
	// TODO: 北兜矪瞶盽Α祘Α絏

	U16 wCardNum = m_Number;

	U8 challenge[32];
	U8 data[32], new_data[32], data1[32]; 
	U8 mac[32];

	U8 page7SavedData[32], page8SavedData[32], page9SavedData[32];

	int result;
	int compareOK = 1;    
	U16 startPage = 0x01;     
	int num_pages_to_test = 1;
	int num_bytes_to_test = 32;

	////////////////////////////

	U8 notUsed[1] = {0};
	U16 zeroLen = 0;
	U16 len32= 32;

	U8 data3[32];
	U8 data4[12];
	U8 data5[1];
	int i,rslt,rt = TRUE;
	int block,skip_setup=FALSE,page,cnt;

	U8 partial[32], new_page[32];
	int current_secret=0,cleared_byte;
	U8 memimage[512]; 
	U8 master_secret[32];
	U8 binding[32];
	U8 romid[8];
	U8 manid[2];

	UCHAR   ITROMId[8];
	UCHAR   ITMANId[2];
	UCHAR   ITmaster_secret[32];
	UCHAR   ITpartial[32];
	UCHAR   ITbinding[32];

	CString strHex;

	// open log file and print time stamp
	CHAR logfile[MAX_PATH];
	CHAR my_documents[MAX_PATH];
    result = SHGetFolderPath(NULL, CSIDL_PERSONAL, NULL, SHGFP_TYPE_CURRENT, my_documents);
	if (result == S_OK)
	{
		sprintf(my_documents, "%s\\ADLINK", my_documents);
		if (CreateDirectory(my_documents, NULL) || ERROR_ALREADY_EXISTS == GetLastError())
		{
		sprintf(logfile,"%s\\log6-1.txt",my_documents);
		DFile = fopen(logfile,"a+");
	}
	}

	if(DFile == NULL)
	{
		printf("ERROR, Could not open LOT.TXT log file!\n");
		exit(1);
	}

	srand((unsigned)time(NULL));


	for (i=0;i<32;i++)
	{
		GetDlgItemText(IDC_EDIT_DCSETBUF0+i, strHex);
		master_secret[i]=(U8)hex2uint(strHex);
	}

	dprintf("master_secret: ");
	for (i = 0; i < 32; i++)
		dprintf("%02X",master_secret[i]);
	dprintf("\n");

	dprintf("AD_SetMasterSecret, wCardNum %d\n",wCardNum);
	rslt = AD_SetMasterSecret(wCardNum, master_secret);

	dprintf(" %s\n",(rslt) ?  "FAIL" : "SUCCESS"); 
	if (rslt) rt = FALSE;


	if (rt == TRUE)
	{
		dprintf("Test Pass!");
	}
	else
	{
		dprintf("Test Fail!");   
	}

	fclose(DFile);
}

void CSamrtPoESampleDlg::OnBnClickedButtonSet29()
{
	// TODO: 北兜矪瞶盽Α祘Α絏

	U16 wCardNum = m_Number;
	CString str,str2,str3,str4;

	//  U8 challenge[32];
	U8 data[32], new_data[32], data1[32]; 
	U8 mac[32];
	U8 read_mac[32];

	U8 page7SavedData[32], page8SavedData[32], page9SavedData[32];

	int result;
	int compareOK = 1;
	//U16 startPage = 0x07;     
	U16 startPage = 0x01;     
	int num_pages_to_test = 1;
	int num_bytes_to_test = 32;

	////////////////////////////

	U8 notUsed[1] = {0};
	U16 zeroLen = 0;
	U16 len32= 32;

	U8 data3[32];
	U8 data4[12];
	U8 data5[1];
	int i,rslt,rt = TRUE;
	int block,skip_setup=FALSE,page,cnt;

	U8 partial[32], new_page[32];
	int current_secret=0,cleared_byte;
	U8 memimage[512]; 
	U8 master_secret[32];
	U8 binding[32];
	U8 romid[8];
	U8 manid[2];
	U8 challenge[8];

	UCHAR   ITROMId[8];
	UCHAR   ITMANId[2];
	UCHAR   ITmaster_secret[32];
	UCHAR   ITpartial[32];
	UCHAR   ITbinding[32];

	// open log file and print time stamp
	CHAR logfile[MAX_PATH];
	CHAR my_documents[MAX_PATH];
    result = SHGetFolderPath(NULL, CSIDL_PERSONAL, NULL, SHGFP_TYPE_CURRENT, my_documents);
	if (result == S_OK)
	{
		sprintf(my_documents, "%s\\ADLINK", my_documents);
		if (CreateDirectory(my_documents, NULL) || ERROR_ALREADY_EXISTS == GetLastError())
		{
		sprintf(logfile,"%s\\log8-2.txt",my_documents);
		DFile = fopen(logfile,"a+");
	}
	}

	if(DFile == NULL)
	{
		printf("ERROR, Could not open LOT.TXT log file!\n");
		exit(1);
	}

	srand((unsigned)time(NULL));

	dprintf("AD_EncryptReadSegment_ex2, wCardNum %d\n",wCardNum);
	rslt = AD_EncryptReadSegment(wCardNum, data, romid, manid, read_mac, challenge);

	dprintf("data: ");
	for (i = 0; i < 32; i++)
		dprintf("%02X",data[i]);
	dprintf("\n");

	dprintf("romid: ");
	for (i = 0; i < 8; i++)
		dprintf("%02X",romid[i]);
	dprintf("\n");

	dprintf("manid: ");
	for (i = 0; i < 2; i++)
		dprintf("%02X",manid[i]);
	dprintf("\n");

	dprintf("read_mac: ");
	for (i = 0; i < 32; i++)
		dprintf("%02X",read_mac[i]);
	dprintf("\n");

	dprintf("challenge: ");
	for (i = 0; i < 8; i++)
		dprintf("%02X",challenge[i]);
	dprintf("\n");

 //	for (i=0;i<16;i++)
	//{
 //  
	//	((CButton*)GetDlgItem(IDC_RADIO1_ON1+(i*2)))->SetCheck( data[i] ==  0x71+i ? 1 : 0);
 //  
	//	((CButton*)GetDlgItem(IDC_RADIO1_OFF1+(i*2)))->SetCheck( data[i] ==  0x61+i ? 1 : 0);
 //  
	//}

	str=""; //data[32] + romid[8] + manid[2] + read_mac[32] + challenge[8]
	for (i=0;i<32;i++)
	{
		str4.Format("%02X", data[i]);
		str += str4;		
	}	
	SetDlgItemText(IDC_EDIT_DCGETBUF0, str);


	for (i=0;i<8;i++)
	{
		str4.Format("%02X", romid[i]);
		str += str4;		
	}

	for (i=0;i<2;i++)
	{
		str4.Format("%02X", manid[i]);
		str += str4;
		
	}

	for (i=0;i<32;i++)
	{
		str4.Format("%02X", read_mac[i]);
		str += str4;		
	}

	for (i=0;i<8;i++)
	{
		str4.Format("%02X", challenge[i]);
		str += str4;		
	}
	SetDlgItemText(IDC_EDIT_DCGETBUF6, str);


	dprintf("AD_EncryptReadSegment:  ----------------------------------");		  
	dprintf(" %s\n",(rslt) ?  "FAIL" : "SUCCESS");
	if (rslt) rt = FALSE;


	if (rt == TRUE)
	{
	   dprintf("Test Pass!");
	}
	else
	{
	   dprintf("Test Fail!");   
	}

	fclose(DFile);

}

void CSamrtPoESampleDlg::OnBnClickedButtonSet30()
{

	// TODO: 北兜矪瞶盽Α祘Α絏

	U16 wCardNum = m_Number;

	U8 data[32], new_data[32], data1[32], enc_data[32]; 
	U8 mac[32];
	U8 read_mac[32];

	U8 page7SavedData[32], page8SavedData[32], page9SavedData[32];

	int result;
	int compareOK = 1; 
	U16 startPage = 0x01;     
	int num_pages_to_test = 1;
	int num_bytes_to_test = 32;

	////////////////////////////

	U8 notUsed[1] = {0};
	U16 zeroLen = 0;
	U16 len32= 32;

	U8 data3[32], chk_mac[32];
	U8 data4[12];
	U8 data5[1];
	int i,rslt,rt = TRUE;
	int block,skip_setup=FALSE,page,cnt;

	U8 partial[32], new_page[32];
	int current_secret=0,cleared_byte;
	U8 memimage[512]; 
	U8 master_secret[32];
	U8 binding[32];
	U8 romid[8];
	U8 manid[2];
	U8 challenge[8];

	UCHAR   ITROMId[8];
	UCHAR   ITMANId[2];
	UCHAR   ITmaster_secret[32];
	UCHAR   ITpartial[32];
	UCHAR   ITbinding[32];

	CString str, strHex;

	// open log file and print time stamp
	CHAR logfile[MAX_PATH];
	CHAR my_documents[MAX_PATH];
    result = SHGetFolderPath(NULL, CSIDL_PERSONAL, NULL, SHGFP_TYPE_CURRENT, my_documents);
	if (result == S_OK)
	{
		sprintf(my_documents, "%s\\ADLINK", my_documents);
		if (CreateDirectory(my_documents, NULL) || ERROR_ALREADY_EXISTS == GetLastError())
		{
		sprintf(logfile,"%s\\log8-5.txt",my_documents);
		DFile = fopen(logfile,"a+");
	}
	}

	if(DFile == NULL)
	{
	  printf("ERROR, Could not open LOT.TXT log file!\n");
	  exit(1);
	}

	srand((unsigned)time(NULL));

	dprintf("num_bytes_to_test: ");
	dprintf("%d",num_bytes_to_test);

	GetDlgItemText(IDC_EDIT_DCGETBUF5, str);//data[32] + romid[8] + manid[2] + enc_data[32] + chk_mac[32] + challenge[8]


	for (i=0;i<32;i++)
	{
		strHex = str[(i*2)+(0*2)];
		strHex = strHex + str[(i*2)+1+(0*2)];
		data[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<8;i++)
	{
		strHex = str[(i*2)+(32*2)];
		strHex = strHex + str[(i*2)+1+(32*2)];
		romid[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<2;i++)
	{
		strHex = str[(i*2)+(40*2)];
		strHex = strHex + str[(i*2)+1+(40*2)];
		manid[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<32;i++)
	{
		strHex = str[(i*2)+(42*2)];
		strHex = strHex + str[(i*2)+1+(42*2)];
		enc_data[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<32;i++)
	{
		strHex = str[(i*2)+(74*2)];
		strHex = strHex + str[(i*2)+1+(74*2)];
		chk_mac[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<8;i++)
	{
		strHex = str[(i*2)+(106*2)];
		strHex = strHex + str[(i*2)+1+(106*2)];
		challenge[i]=(U8)hex2uint(strHex);
	}

	dprintf("AD_EncryptAuthWritePageEnc_ex2, wCardNum %d\n",wCardNum);
	rslt = AD_EncryptAuthWritePageEnc(wCardNum, num_bytes_to_test, enc_data, data, romid, manid, chk_mac, challenge, false);


	dprintf("enc_data: ");
	for (i = 0; i < num_bytes_to_test; i++)
		dprintf("%02X",enc_data[i]);
	dprintf("\n");

	dprintf("data: ");
	for (i = 0; i < 32; i++)
		dprintf("%02X",data[i]);
	dprintf("\n");

	dprintf("romid: ");
	for (i = 0; i < 8; i++)
		dprintf("%02X",romid[i]);
	dprintf("\n");

	dprintf("manid: ");
	for (i = 0; i < 2; i++)
		dprintf("%02X",manid[i]);
	dprintf("\n");

	dprintf("chk_mac: ");
	for (i = 0; i < 32; i++)
		dprintf("%02X",chk_mac[i]);
	dprintf("\n");

	dprintf("challenge: ");
	for (i = 0; i < 8; i++)
		dprintf("%02X",challenge[i]);
	dprintf("\n");


	dprintf("AD_EncryptAuthWritePageEnc_ex2: ----------------------------------");		  
	dprintf(" %s\n",(rslt) ?  "FAIL" : "SUCCESS");
	if (rslt) rt = FALSE;

	dprintf("AD_EncryptReadSegment, wCardNum %d\n",wCardNum);
	rslt = AD_EncryptReadSegment(wCardNum, data1, romid, manid, chk_mac, challenge);


	dprintf("data1: ");
	for (i = 0; i < 32; i++)
		dprintf("%02X",data1[i]);
	dprintf("\n");

	dprintf("romid: ");
	for (i = 0; i < 8; i++)
		dprintf("%02X",romid[i]);
	dprintf("\n");

	dprintf("manid: ");
	for (i = 0; i < 2; i++)
		dprintf("%02X",manid[i]);
	dprintf("\n");


	dprintf("AD_EncryptReadSegment_ex2:  ----------------------------------");		  
	dprintf(" %s\n",(rslt) ?  "FAIL" : "SUCCESS");
	if (rslt) rt = FALSE;


	if (rt == TRUE)
	{
	   dprintf("Test Pass!");
	}
	else
	{
	   dprintf("Test Fail!");   
	}

	fclose(DFile);

}

void CSamrtPoESampleDlg::OnBnClickedButtonSet31()
{

	// TODO: 北兜矪瞶盽Α祘Α絏

	U16 wCardNum = m_Number;

	CString str,str2,str3,str4;
	U8 data[32], new_data[32], data1[32], enc_data[32], chk_mac[32]; 
	U8 mac[32];
	U8 read_mac[32];

	U8 page7SavedData[32], page8SavedData[32], page9SavedData[32];

	int result;
	int compareOK = 1;  
	U16 startPage = 0x01;     
	int num_pages_to_test = 1;
	int num_bytes_to_test = 32;

	////////////////////////////

	U8 notUsed[1] = {0};
	U16 zeroLen = 0;
	U16 len32= 32;

	U8 data3[32];
	U8 data4[12];
	U8 data5[1];
	int i,rslt,rt = TRUE;
	int block,skip_setup=FALSE,page,cnt;

	U8 partial[32], new_page[32];
	int current_secret=0,cleared_byte;
	U8 memimage[512]; 
	U8 master_secret[32];
	U8 binding[32];
	U8 romid[8];
	U8 manid[2];
	U8 challenge[8];

	UCHAR   ITROMId[8];
	UCHAR   ITMANId[2];
	UCHAR   ITmaster_secret[32];
	UCHAR   ITpartial[32];
	UCHAR   ITbinding[32];

	CString strHex;

	// open log file and print time stamp
	CHAR logfile[MAX_PATH];
	CHAR my_documents[MAX_PATH];
    result = SHGetFolderPath(NULL, CSIDL_PERSONAL, NULL, SHGFP_TYPE_CURRENT, my_documents);
	if (result == S_OK)
	{
		sprintf(my_documents, "%s\\ADLINK", my_documents);
		if (CreateDirectory(my_documents, NULL) || ERROR_ALREADY_EXISTS == GetLastError())
		{
		sprintf(logfile,"%s\\log8-4.txt",my_documents);
		DFile = fopen(logfile,"a+");
	}
	}

	if(DFile == NULL)
	{
		printf("ERROR, Could not open LOT.TXT log file!\n");
		exit(1);
	}

	srand((unsigned)time(NULL));

	dprintf("num_bytes_to_test: ");
	dprintf("%d",num_bytes_to_test);

	GetDlgItemText(IDC_EDIT_DCGETBUF6, str);//data[32] + romid[8] + manid[2] + read_mac[32] + challenge[8];

	for (i=0;i<32;i++)
	{
		strHex = str[(i*2)+(0*2)];
		strHex = strHex + str[(i*2)+1+(0*2)];
		data[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<8;i++)
	{
		strHex = str[(i*2)+(32*2)];
		strHex = strHex + str[(i*2)+1+(32*2)];
		romid[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<2;i++)
	{
		strHex = str[(i*2)+(40*2)];
		strHex = strHex + str[(i*2)+1+(40*2)];
		manid[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<32;i++)
	{
		strHex = str[(i*2)+(42*2)];
		strHex = strHex + str[(i*2)+1+(42*2)];
		read_mac[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<8;i++)
	{
		strHex = str[(i*2)+(74*2)];
		strHex = strHex + str[(i*2)+1+(74*2)];
		challenge[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<16;i++)
	{
        new_data[i] = (U8)((CButton*)GetDlgItem(IDC_RADIO1_ON1 + (i*2)))->GetCheck() ? 0x71+i : 0x61+i;
	}

	for (i=16;i<32;i++)
	{
        new_data[i] = (U8)0;
	}

	dprintf("AD_EncryptComputeEnc_ex2, wCardNum %d\n",wCardNum);
	rslt = AD_EncryptComputeEnc(wCardNum, new_data, romid, manid, read_mac, challenge, enc_data, chk_mac);

	dprintf("enc_data: ");
	for (i = 0; i < num_bytes_to_test; i++)
		dprintf("%02X",enc_data[i]);
	dprintf("\n");

	dprintf("chk_mac: ");
	for (i = 0; i < num_bytes_to_test; i++)
		dprintf("%02X",chk_mac[i]);
	dprintf("\n");

	dprintf("data: ");
	for (i = 0; i < 32; i++)
		dprintf("%02X",data[i]);
	dprintf("\n");

	dprintf("romid: ");
	for (i = 0; i < 8; i++)
		dprintf("%02X",romid[i]);
	dprintf("\n");

	dprintf("manid: ");
	for (i = 0; i < 2; i++)
		dprintf("%02X",manid[i]);
	dprintf("\n");

	dprintf("read_mac: ");
	for (i = 0; i < 32; i++)
		dprintf("%02X",read_mac[i]);
	dprintf("\n");

	dprintf("challenge: ");
	for (i = 0; i < 8; i++)
		dprintf("%02X",challenge[i]);
	dprintf("\n");


	str=""; //data[32] + romid[8] + manid[2] + enc_data[32] + chk_mac[32] + challenge[8]
	for (i=0;i<32;i++)
	{
		str4.Format("%02X", data[i]);
		str += str4;		
	}
	SetDlgItemText(IDC_EDIT_DCGETBUF0, str);

	for (i=0;i<8;i++)
	{
		str4.Format("%02X", romid[i]);
		str += str4;		
	}

	for (i=0;i<2;i++)
	{
		str4.Format("%02X", manid[i]);
		str += str4;		
	}

	for (i=0;i<32;i++)
	{
		str4.Format("%02X", enc_data[i]);
		str += str4;		
	}

	for (i=0;i<32;i++)
	{
		str4.Format("%02X", chk_mac[i]);
		str += str4;		
	}

	for (i=0;i<8;i++)
	{
		str4.Format("%02X", challenge[i]);
		str += str4;		
	}
	SetDlgItemText(IDC_EDIT_DCGETBUF5, str);//data[32] + romid[8] + manid[2] + enc_data[32] + chk_mac[32] + challenge[8]


	dprintf("AD_EncryptComputeEnc_ex2: ----------------------------------");		  
	dprintf(" %s\n",(rslt) ?  "FAIL" : "SUCCESS");
	if (rslt) rt = FALSE;

	if (rt == TRUE)
	{
		dprintf("Test Pass!");
	}
	else
	{
		dprintf("Test Fail!");   
	}

	fclose(DFile);

}

void CSamrtPoESampleDlg::OnBnClickedButtonSet32()
{

	U16 wCardNum = m_Number;
	U8 InstallBit;
	U8 LockDataBit;
	int err;

	// bitsatus = 0 (Non-burned card)
    // bitsatus = 1 (Burned card)
    // bitsatus = 2 (Burned card and data locked)
    // lockstatus = 0 (Secret non-locked)
    // lockstatus = 1 (Secret locked)

	err = AD_ReadInstallSecretStatus(wCardNum, &InstallBit, &LockDataBit);
	
	CString info;
	info.Format("Card Status:%d,Secret Status:%d", InstallBit, LockDataBit);

	MessageBox(info,"InstallSecretStatus");
}


void CSamrtPoESampleDlg::OnBnClickedButtonSet33()
{

	U16 wCardNum = m_Number;

	CString str,str2,str3,str4;
	U8 challenge[32];
	U8 data[32], new_data[32], data1[32], enc_data[32], chk_mac[32]; 
	U8 mac[32];
	U8 read_mac[32];

	U8 page7SavedData[32], page8SavedData[32], page9SavedData[32];

	int result;
	int compareOK = 1;
	//U16 startPage = 0x07;     
	U16 startPage = 0x01;     
	int num_pages_to_test = 1;
	int num_bytes_to_test = 32;

	////////////////////////////

	U8 notUsed[1] = {0};
	U16 zeroLen = 0;
	U16 len32= 32;

	U8 data3[32];
	U8 data4[12];
	U8 data5[1];
	int i,rslt = FALSE,rt = TRUE;
	int block,skip_setup=FALSE,page,cnt;

	U8 partial[32], new_page[32];
	int current_secret=0,cleared_byte;
	U8 memimage[512]; 
	U8 master_secret[32];
	U8 binding[32];
	U8 romid[8];
	U8 manid[2];

	UCHAR   ITROMId[8];
	UCHAR   ITMANId[2];
	UCHAR   ITmaster_secret[32];
	UCHAR   ITpartial[32];
	UCHAR   ITbinding[32];

	CString strHex;

	// open log file and print time stamp
	CHAR logfile[MAX_PATH];
	CHAR my_documents[MAX_PATH];
    result = SHGetFolderPath(NULL, CSIDL_PERSONAL, NULL, SHGFP_TYPE_CURRENT, my_documents);
	if (result == S_OK)
	{
		sprintf(my_documents, "%s\\ADLINK", my_documents);
		if (CreateDirectory(my_documents, NULL) || ERROR_ALREADY_EXISTS == GetLastError())
		{
		sprintf(logfile,"%s\\log8-6.txt",my_documents);
		DFile = fopen(logfile,"a+");
	}
	}

	if(DFile == NULL)
	{
	printf("ERROR, Could not open LOT.TXT log file!\n");
	exit(1);
	}

	srand((unsigned)time(NULL));

	dprintf("num_bytes_to_test: ");
	dprintf("%d",num_bytes_to_test);

	GetDlgItemText(IDC_EDIT_DCGETBUF6, str);//data[32] + romid[8] + manid[2] + read_mac[32];

	for (i=0;i<32;i++)
	{
		strHex = str[(i*2)+(0*2)];
		strHex = strHex + str[(i*2)+1+(0*2)];
		data[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<8;i++)
	{
		strHex = str[(i*2)+(32*2)];
		strHex = strHex + str[(i*2)+1+(32*2)];
		romid[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<2;i++)
	{
		strHex = str[(i*2)+(40*2)];
		strHex = strHex + str[(i*2)+1+(40*2)];
		manid[i]=(U8)hex2uint(strHex);
	}

	for (i=0;i<32;i++)
	{
		strHex = str[(i*2)+(42*2)];
		strHex = strHex + str[(i*2)+1+(42*2)];
		read_mac[i]=(U8)hex2uint(strHex);
	}


	for (i=0;i<16;i++)
	{
		((CButton*)GetDlgItem(IDC_RADIO1_ON1+(i*2)))->SetCheck( data[i] ==  0x71+i ? 1 : 0);
		((CButton*)GetDlgItem(IDC_RADIO1_OFF1+(i*2)))->SetCheck( data[i] ==  0x61+i ? 1 : 0);
	}

	dprintf("data: ");
	for (i = 0; i < 32; i++)
		dprintf("%02X",data[i]);
	dprintf("\n");

	dprintf("romid: ");
	for (i = 0; i < 8; i++)
		dprintf("%02X",romid[i]);
	dprintf("\n");

	dprintf("manid: ");
	for (i = 0; i < 2; i++)
		dprintf("%02X",manid[i]);
	dprintf("\n");

	dprintf("data: ");
	for (i = 0; i < 32; i++)
		dprintf("%02X",read_mac[i]);
	dprintf("\n");

	dprintf("Check ON/OFF: ----------------------------------");		  
	dprintf(" %s\n",(rslt) ?  "FAIL" : "SUCCESS");
	if (rslt) rt = FALSE;

	if (rt == TRUE)
	{
		dprintf("Test Pass!");
	}
	else
	{
		dprintf("Test Fail!");   
	}

	fclose(DFile);

}


